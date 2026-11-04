import Foundation

/// Learns from what Moe commits in the keyboard (SPEC 9.2). The last committed word stays pending
/// until the next commit, a sentence end or flush, so backspacing into it can still drop it.
/// Final events are batched and written at most every learnerFlushSeconds (checked on each call,
/// or by writeIfDue) and on flush. Confined to the engine queue.
public final class Learner {
    public enum Commit {
        case typed  // typed + space or punctuation
        case suggestion  // a suggestion tap
        case literal  // tapping the quoted literal: an explicit accept
        case autocorrect(from: String)  // replaced the typed literal
    }

    private struct Event {
        let word: String
        let kind: Token.Kind
        let context: [String]
        let commit: Commit
        let time: Double
    }

    private let store: PersonalStore?
    private let model: PersonalModel?
    private let config: EngineConfig
    private let clock: () -> Date
    /// The current field; learning stops in URL, password and one-time-code fields.
    public var traits = FieldTraits()
    /// The "Pause learning" setting.
    public var paused = false
    private var session = 0
    private var pending: Event?
    private var batch: LearningBatch
    private var lastWrite: Double
    private var reopened: (ident: String, kind: Token.Kind, time: Double)?  // for manual-correction learning

    public init(store: PersonalStore?, model: PersonalModel?, config: EngineConfig = EngineConfig(), clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.model = model
        self.config = config
        self.clock = clock
        batch = LearningBatch(halfLife: config.halfLife)
        lastWrite = clock().timeIntervalSince1970
    }

    private var now: Double { clock().timeIntervalSince1970 }
    private var learning: Bool { traits.allowsLearning && !paused }

    /// Call each time the keyboard appears.
    public func startSession(id: Int = Int.random(in: 1...Int.max)) {
        session = id
    }

    /// A word was committed after its context (up to 2 previous words, oldest first; <s> or empty
    /// at a sentence start).
    public func commit(_ word: String, lang: Lang, context: [String], how: Commit) {
        guard learning else { return }
        finalizePending()
        let kind = Self.kind(of: word, lang: lang)
        let wordIdent = ident(word, kind: kind)
        if let reopened, reopened.kind == kind, now - reopened.time <= config.manualCorrectionSeconds,
           reopened.ident != wordIdent, editDistance(reopened.ident, wordIdent) <= config.manualCorrectionMaxDistance {
            batch.addCorrection(lang: kind.storeLang, typed: reopened.ident, chosen: wordIdent, rejected: false, at: now)
        }
        reopened = nil
        pending = Event(word: word, kind: kind, context: Self.sameRun(context, kind: kind), commit: how, time: now)
        writeIfDue()
    }

    public func sentenceEnded() {
        finalizePending()
        writeIfDue()
    }

    /// Backspace moved the cursor into a committed word: a pending event for it is dropped, and a
    /// different word committed there within manualCorrectionSeconds is learned as its correction.
    public func backspaced(into word: String, lang: Lang) {
        if pending?.word == word { pending = nil }
        let kind = Self.kind(of: word, lang: lang)
        reopened = (ident(word, kind: kind), kind, now)
    }

    /// One-backspace undo of the pending autocorrect: records the rejection (effective at once) and
    /// keeps the literal as an explicit accept.
    public func undoAutocorrect() {
        guard let event = pending, case .autocorrect(let literal) = event.commit else { return }
        let typed = ident(literal, kind: event.kind), chosen = ident(event.word, kind: event.kind)
        model?.addRejection(lang: event.kind.storeLang, typed: typed, chosen: chosen)
        batch.addCorrection(lang: event.kind.storeLang, typed: typed, chosen: chosen, rejected: true, at: now)
        pending = Event(word: literal, kind: event.kind, context: event.context, commit: .literal, time: event.time)
    }

    /// On dismiss (viewWillDisappear): everything pending becomes final and is written.
    public func flush() {
        finalizePending()
        write()
    }

    public func writeIfDue() {
        if now - lastWrite >= config.learnerFlushSeconds { write() }
    }

    /// UILexicon entries (contact names, text replacements) become known words with source lexicon.
    public func addLexiconEntries(_ entries: [String]) {
        for entry in entries {
            for token in tokenize(entry) where token.kind != .sentenceEnd {
                batch.addWord(token.surface, kind: token.kind, context: [], at: now, source: .lexicon)
            }
        }
        write()
    }

    private func finalizePending() {
        guard let event = pending else { return }
        pending = nil
        var explicit = false
        if case .literal = event.commit { explicit = true }
        batch.addWord(event.word, kind: event.kind, context: event.context, at: event.time, source: .typed,
                      session: session, explicit: explicit)
    }

    /// One transaction. On failure the batch is kept and retried with the next write.
    private func write() {
        guard !batch.isEmpty, let store else { return }
        do {
            try store.write(batch)
            model?.refresh(after: batch)
            batch = LearningBatch(halfLife: config.halfLife)
            lastWrite = now
        } catch {
            personalLog.error("learner write failed, kept for retry: \(String(describing: error), privacy: .public)")
        }
    }

    private static func kind(of word: String, lang: Lang) -> Token.Kind {
        isSpecial(word) ? .tok : lang == .en ? .en : .ar
    }

    /// The trailing context words of the word's own language run (SPEC 9.3 splits runs by script).
    private static func sameRun(_ context: [String], kind: Token.Kind) -> [String] {
        guard kind != .tok else { return [] }
        guard !context.isEmpty else { return [sentenceStart] }
        let run = context.suffix(2).reversed().prefix { $0 == sentenceStart || tokenize($0).first?.kind == kind }
        return run.reversed().map { $0 == sentenceStart ? $0 : ident($0, kind: kind) }
    }
}

/// Levenshtein distance over Unicode scalars.
func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
    var row = Array(0...b.count)
    for (i, x) in a.enumerated() {
        var diagonal = row[0]
        row[0] = i + 1
        for (j, y) in b.enumerated() {
            let above = row[j + 1]
            row[j + 1] = min(above + 1, row[j] + 1, diagonal + (x == y ? 0 : 1))
            diagonal = above
        }
    }
    return row[b.count]
}
