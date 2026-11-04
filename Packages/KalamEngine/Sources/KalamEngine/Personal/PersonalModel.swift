import Foundation
import os

let personalLog = Logger(subsystem: "com.morad.kalam", category: "personal")

/// Personal n-gram counts after one context, decayed to the request time.
struct ContextCounts {
    let trigram: [String: Double]  // Cu(a, b, w)
    let bigram: [String: Double]  // Cu(b, w)
    let trigramTotal: Double
    let bigramTotal: Double

    init(trigram: [String: Double] = [:], bigram: [String: Double] = [:]) {
        (self.trigram, self.bigram) = (trigram, bigram)
        (trigramTotal, bigramTotal) = (trigram.values.reduce(0, +), bigram.values.reduce(0, +))
    }
}

/// What a suggestion request needs from the personal store, held in memory (SPEC 8.2 to 8.4): the
/// personal tries of known words, blocked words, corpus sizes, corrections and key offsets are loaded
/// once; the continuations of a context are loaded once per context. Confined to the engine queue.
/// A store error degrades to base-only suggestions and is logged.
public final class PersonalModel {
    let store: PersonalStore?
    let config: EngineConfig
    let clock: () -> Date
    private var tries: [String: PersonalTrie] = [:]  // by store lang: en, ar, tok
    private var blocked: [String: Set<String>] = [:]
    private var totals: [String: Hits] = [:]  // Nu
    private var corrections: Set<LearningBatch.CorrectionKey> = []
    private var confusions: [String: Set<UInt32>] = [:]  // by store lang, from corrections
    private var keyOffsets: [String: [String: KeyOffset]] = [:]  // by store lang, then key output
    private var spatialModels: [Lang: SpatialModel] = [:]  // built from keyOffsets on first use
    private var contexts: [[String]: ContextCounts] = [:]
    private static let contextCacheSize = 8

    public init(store: PersonalStore?, config: EngineConfig = EngineConfig(), clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.config = config
        self.clock = clock
        load()
    }

    var now: Double { clock().timeIntervalSince1970 }

    private func load() {
        guard let store else { return }
        do {
            for lang in ["en", "ar", "tok"] {
                let rows = try store.words(lang: lang)
                var trie = PersonalTrie(cap: config.personalTrieCap, halfLife: config.halfLife)
                let known = rows.filter { $0.state == .known }.sorted { $0.hits.rank(halfLife: config.halfLife) > $1.hits.rank(halfLife: config.halfLife) }
                for row in known.prefix(config.personalTrieCap) { trie.set(row.ident, norm: row.norm, display: row.display, hits: row.hits) }
                tries[lang] = trie
                blocked[lang] = Set(rows.filter { $0.state == .blocked }.map(\.ident))
                totals[lang] = rows.reduce(into: Hits()) { $0.add($1.hits.count, at: $1.hits.time, halfLife: config.halfLife) }
            }
            corrections = Set(try store.corrections())
            keyOffsets = try ["en", "ar"].reduce(into: [:]) { $0[$1] = try store.keyOffsets(lang: $1) }
        } catch {
            personalLog.error("personal load failed, base-only: \(String(describing: error), privacy: .public)")
            (tries, blocked, totals, corrections, keyOffsets) = ([:], [:], [:], [], [:])
        }
        confusions = KalamEngine.confusionPairs(corrections, minCorrections: config.learnedConfusionMinCorrections)
    }

    // MARK: Engine reads

    func trie(_ lang: Lang) -> PersonalTrie? { tries[lang.rawValue] }

    /// Decayed personal count of a known word.
    func count(_ lang: Lang, _ ident: String) -> Double {
        tries[lang.rawValue]?.words[ident]?.hits.value(at: now, halfLife: config.halfLife) ?? 0
    }

    func corpusSize(_ lang: Lang) -> Double { totals[lang.rawValue]?.value(at: now, halfLife: config.halfLife) ?? 0 }
    func display(_ lang: Lang, _ ident: String) -> String? { tries[lang.rawValue]?.words[ident]?.display }
    func isKnown(_ lang: Lang, _ ident: String) -> Bool { tries[lang.rawValue]?.words[ident] != nil }
    func isBlocked(_ lang: Lang, _ ident: String) -> Bool { blocked[lang.rawValue]?.contains(ident) == true }

    func hasCorrection(_ lang: Lang, typed: String, chosen: String, rejected: Bool) -> Bool {
        corrections.contains(LearningBatch.CorrectionKey(lang: lang.rawValue, typed: typed, chosen: chosen, rejected: rejected))
    }

    /// The spatial model with Moe's learned key offsets (SPEC 8.2), the fixed offset where there are none.
    func spatialModel(_ lang: Lang, layout: Layout?) -> SpatialModel {
        if let model = spatialModels[lang] { return model }
        let offsets = KeyOffsets(keyOffsets[lang.rawValue] ?? [:], config: config)
        let model = SpatialModel(layout: layout, offset: offsets.offset)
        spatialModels[lang] = model
        return model
    }

    /// (typed, intended) char pairs that get the learned confusion cost (SPEC 8.2).
    func confusionPairs(_ lang: Lang) -> Set<UInt32> { confusions[lang.rawValue] ?? [] }

    /// Known special tokens starting with the typed text, case-insensitively.
    func tokens(withPrefix prefix: String) -> [PersonalTrie.Word] {
        let prefix = prefix.lowercased()
        return tries["tok"]?.words.filter { $0.key.lowercased().hasPrefix(prefix) }.map(\.value) ?? []
    }

    /// How often Moe kept a word as typed. One store read, for the autocorrect variant fix only.
    func uses(_ lang: Lang, _ ident: String) -> Int {
        do {
            return try store?.uses(lang: lang.rawValue, ident: ident) ?? 0
        } catch {
            personalLog.error("uses read failed: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    /// Raw uses + imports of a word and whether it's a recorded typo: one store read, made only for
    /// an autocorrect about to happen (SPEC 8.5 rule 2).
    func usage(_ lang: Lang, _ ident: String) -> (uses: Int, recordedTypo: Bool) {
        do {
            return try store?.usage(lang: lang.rawValue, ident: ident) ?? (0, false)
        } catch {
            personalLog.error("usage read failed: \(String(describing: error), privacy: .public)")
            return (0, false)
        }
    }

    /// Continuations of (a, b) and of (b), loaded from the store once per context.
    func context(_ lang: Lang, _ idents: [String]) -> ContextCounts {
        let key = [lang.rawValue] + idents
        if let cached = contexts[key] { return cached }
        var counts = ContextCounts()
        if let store, let b = idents.last {
            do {
                let now = self.now, halfLife = config.halfLife
                let bigram = try store.continuations(lang: lang.rawValue, w1: "", w2: b).mapValues { $0.value(at: now, halfLife: halfLife) }
                let trigram = idents.count == 2
                    ? try store.continuations(lang: lang.rawValue, w1: idents[0], w2: b).mapValues { $0.value(at: now, halfLife: halfLife) } : [:]
                counts = ContextCounts(trigram: trigram, bigram: bigram)
            } catch {
                personalLog.error("context read failed: \(String(describing: error), privacy: .public)")
                counts = ContextCounts()
            }
        }
        if contexts.count >= Self.contextCacheSize { contexts.removeAll() }
        contexts[key] = counts
        return counts
    }

    // MARK: Updates

    /// An autocorrect undo: takes effect at once, before the learner's batched write.
    func addRejection(lang: String, typed: String, chosen: String) {
        corrections.insert(LearningBatch.CorrectionKey(lang: lang, typed: typed, chosen: chosen, rejected: true))
    }

    /// Re-reads the words and key offsets a written batch touched, so the tries follow the store's
    /// state rules and the spatial model the new means.
    func refresh(after batch: LearningBatch) {
        contexts.removeAll()
        corrections.formUnion(batch.corrections.keys)
        if batch.corrections.keys.contains(where: { !$0.rejected }) {
            confusions = KalamEngine.confusionPairs(corrections, minCorrections: config.learnedConfusionMinCorrections)
        }
        do {
            for (key, update) in batch.words {
                totals[key.lang, default: Hits()].add(update.hits.count, at: update.hits.time, halfLife: config.halfLife)
                guard let row = try store?.word(lang: key.lang, ident: key.ident) else { continue }
                apply(row, lang: key.lang)
            }
            for lang in Set(batch.keyOffsets.keys.map(\.lang)) {
                keyOffsets[lang] = try store?.keyOffsets(lang: lang)
                if let lang = Lang(rawValue: lang) { spatialModels[lang] = nil }
            }
        } catch {
            personalLog.error("personal refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Forget (SPEC 5.4): blocks the word in the store and drops it from suggestions at once.
    public func block(_ lang: Lang, _ ident: String, display: String) {
        do {
            try store?.block(lang: lang.rawValue, ident: ident, display: display, now: now)
        } catch {
            personalLog.error("block failed: \(String(describing: error), privacy: .public)")
        }
        apply(WordRow(ident: ident, norm: "", display: display, hits: Hits(), state: .blocked), lang: lang.rawValue)
    }

    private func apply(_ row: WordRow, lang: String) {
        switch row.state {
        case .known:
            tries[lang, default: PersonalTrie(cap: config.personalTrieCap, halfLife: config.halfLife)]
                .set(row.ident, norm: row.norm, display: row.display, hits: row.hits)
            blocked[lang]?.remove(row.ident)
        case .blocked:
            tries[lang]?.remove(row.ident)
            blocked[lang, default: []].insert(row.ident)
        case .pending:
            break
        }
    }
}
