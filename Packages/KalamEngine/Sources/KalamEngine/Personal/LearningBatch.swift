import Foundation

/// A decayed count (SPEC 8.4): `count` as of `time` (seconds since 1970), halving every half-life.
struct Hits: Equatable {
    var count = 0.0
    var time = 0.0

    func value(at now: Double, halfLife: Double) -> Double { count * exp2(-(now - time) / halfLife) }

    /// Adds n hits at time t, merged at the later of the two times (imports can be older than t_last).
    mutating func add(_ n: Double, at t: Double, halfLife: Double) {
        let latest = max(time, t)
        count = value(at: latest, halfLife: halfLife) + n * exp2(-(latest - t) / halfLife)
        time = latest
    }

    /// Orders hits by decayed value at any common `now`, without knowing it:
    /// ln(value(now)) = rank - now * ln2 / halfLife.
    func rank(halfLife: Double) -> Double { log(count) + time * M_LN2 / halfLife }
}

public enum WordSource: String, Sendable {
    case typed, `import`, lexicon, manual
}

extension Token.Kind {
    /// The store's lang column: en, ar or tok.
    var storeLang: String {
        switch self {
        case .en: return "en"
        case .ar: return "ar"
        case .tok, .sentenceEnd: return "tok"
        }
    }
}

/// Learning updates aggregated in memory and written by PersonalStore in short transactions.
struct LearningBatch {
    struct WordKey: Hashable {
        let lang: String
        let ident: String
    }

    struct WordUpdate {
        var hits = Hits()
        var uses = 0  // typed commits
        var imports = 0  // import occurrences that may promote the word
        var explicit = false
        var source: WordSource
        var session: Int?
        var display: String  // latest surface, used when the row is new
        var votes: [String: Int] = [:]  // display form votes (SPEC 6.3: Moe's most frequent form)
    }

    struct NgramKey: Hashable {
        let lang: String
        let w1: String  // "" for bigrams
        let w2: String
        let w3: String
    }

    struct CorrectionKey: Hashable {
        let lang: String
        let typed: String
        let chosen: String
        let rejected: Bool
    }

    struct KeyOffsetKey: Hashable {
        let lang: String
        let key: String  // the key's output on the letters page
    }

    let halfLife: Double
    var words: [WordKey: WordUpdate] = [:]
    var ngrams: [NgramKey: Hits] = [:]
    var corrections: [CorrectionKey: Hits] = [:]
    var keyOffsets: [KeyOffsetKey: [Point]] = [:]  // tap - key center samples, in commit order

    var isEmpty: Bool { words.isEmpty && ngrams.isEmpty && corrections.isEmpty && keyOffsets.isEmpty }

    /// One use of a word after its context (≤ 2 idents of the same run, oldest first, maybe starting with <s>).
    mutating func addWord(_ surface: String, kind: Token.Kind, context: [String], at time: Double,
                          source: WordSource, session: Int? = nil, explicit: Bool = false) {
        let lang = kind.storeLang
        let ident = KalamEngine.ident(surface, kind: kind)
        var update = words[WordKey(lang: lang, ident: ident)] ?? WordUpdate(source: source, display: surface)
        update.hits.add(1, at: time, halfLife: halfLife)
        update.uses += source == .typed ? 1 : 0
        update.imports += source == .import ? 1 : 0
        update.explicit = update.explicit || explicit
        update.session = session ?? update.session
        update.display = surface
        // Auto-shift capitalizes sentence starts, so those don't vote on casing.
        if context.last != sentenceStart || surface.first?.isUppercase != true { update.votes[surface, default: 0] += 1 }
        words[WordKey(lang: lang, ident: ident)] = update

        guard kind != .tok, let b = context.last else { return }
        ngrams[NgramKey(lang: lang, w1: "", w2: b, w3: ident), default: Hits()].add(1, at: time, halfLife: halfLife)
        if context.count == 2 {
            ngrams[NgramKey(lang: lang, w1: context[0], w2: b, w3: ident), default: Hits()].add(1, at: time, halfLife: halfLife)
        }
    }

    mutating func addCorrection(lang: String, typed: String, chosen: String, rejected: Bool, count: Double = 1, at time: Double) {
        corrections[CorrectionKey(lang: lang, typed: typed, chosen: chosen, rejected: rejected), default: Hits()]
            .add(count, at: time, halfLife: halfLife)
    }

    /// SPEC 9.2: the tap offset samples of a word committed as typed or autocorrected.
    mutating func addKeyOffsets(_ word: String, taps: [Tap], layout: Layout) {
        for sample in offsetSamples(word, taps: taps, layout: layout) {
            keyOffsets[KeyOffsetKey(lang: layout.lang.rawValue, key: sample.key), default: []].append(sample.offset)
        }
    }

    /// Moves n-gram counts from spellings to the words they stand for, in every position.
    mutating func respell(_ spellings: [String: String], lang: String) {
        guard !spellings.isEmpty else { return }
        var respelled: [NgramKey: Hits] = [:]
        for (key, hits) in ngrams {
            let new = key.lang != lang ? key : NgramKey(lang: lang, w1: spellings[key.w1] ?? key.w1,
                                                         w2: spellings[key.w2] ?? key.w2, w3: spellings[key.w3] ?? key.w3)
            respelled[new, default: Hits()].add(hits.count, at: hits.time, halfLife: halfLife)
        }
        ngrams = respelled
    }

    /// Every word of a text (an imported message, pasted text) with its context.
    mutating func addText(_ text: String, at time: Double, source: WordSource) {
        for (token, context) in contextualWords(text) {
            addWord(token.surface, kind: token.kind, context: context, at: time, source: source)
        }
    }
}

/// The words of a text, each with its n-gram context (SPEC 9.3): up to 2 previous idents of the same
/// language run, with <s> at a sentence start. A language switch starts a run with no context;
/// special tokens get none and break the run.
public func contextualWords(_ text: String) -> [(token: Token, context: [String])] {
    var result: [(token: Token, context: [String])] = []
    var context = [sentenceStart]
    var runKind: Token.Kind?
    for token in tokenize(text) {
        switch token.kind {
        case .sentenceEnd:
            context = [sentenceStart]
            runKind = nil
        case .tok:
            result.append((token, []))
            context = []
            runKind = nil
        case .en, .ar:
            if let runKind, runKind != token.kind { context = [] }
            result.append((token, context))
            context = Array((context + [token.ident]).suffix(2))
            runKind = token.kind
        }
    }
    return result
}
