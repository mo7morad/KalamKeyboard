// KalamEngine: keyboard engine shared by the extension, the host app and kalam-cli.
// Never import UIKit here (CLAUDE.md hard rule 3).
import Foundation

/// One typed character. Point is the commit point in key units, nil for point-less input (SPEC 8.1).
public struct Tap: Sendable {
    public var char: String
    public var point: Point?

    public init(_ char: String, at point: Point? = nil) {
        self.char = char
        self.point = point
    }
}

public struct InputState: Sendable {
    /// Up to 2 context words, oldest first (made into idents by the engine); empty means sentence start.
    public var context: [String]
    public var taps: [Tap]

    public init(context: [String], taps: [Tap]) {
        self.context = context
        self.taps = taps
    }

    public var literal: String { taps.map(\.char).joined() }
}

/// A ranked candidate with its score breakdown (SPEC 8.3).
public struct Suggestion: Sendable {
    public let text: String  // display form: Moe's casing, else the corpus casing table
    public let ident: String
    public let isLiteral: Bool
    public let lm: Double
    public let spatial: Double  // already weighted by alpha
    public let edits: Double
    public let completion: Double
    public let boosts: Double

    public var score: Double { lm - spatial - edits - completion + boosts }
}

/// Confined to the engine queue, like the PersonalModel it reads.
public struct Engine {
    public let lang: Lang
    public let config: EngineConfig
    let lexicon: BaseLexicon?
    let layout: Layout?
    /// With the fixed tap offset only; a personal model supplies one with Moe's learned offsets.
    let fixedSpatial: SpatialModel
    let personal: PersonalModel?

    /// A missing lexicon, or one for another language, leaves only the literal and personal candidates.
    public init(lang: Lang, lexicon: BaseLexicon?, layout: Layout?, personal: PersonalModel? = nil, config: EngineConfig = EngineConfig()) {
        self.lang = lang
        self.lexicon = lexicon?.lang == lang ? lexicon : nil
        self.layout = layout?.lang == lang ? layout : nil
        fixedSpatial = SpatialModel(layout: self.layout) { _ in Point(x: config.tapOffsetX, y: config.tapOffsetY) }
        self.personal = personal
        self.config = config
    }

    var kind: Token.Kind { lang == .en ? .en : .ar }

    public func suggest(_ input: InputState, limit: Int = 3) -> [Suggestion] {
        Array(candidates(input).prefix(limit))
    }

    /// Every candidate for the current word, best first: base and personal trie matches merged by
    /// ident, the literal, and known special tokens it starts. Blocked words are dropped.
    public func candidates(_ input: InputState) -> [Suggestion] {
        let literal = input.literal
        guard !literal.isEmpty else { return [] }
        let context = lmContext(input.context)
        let literalIdent = ident(literal, kind: kind)
        let (taps, explicitChars) = searchTaps(input.taps)
        let paths = searchBothTries(taps, literalLength: literal.count)

        var results: [Suggestion] = paths.compactMap { ident, path in
            guard ident == literalIdent || personal?.isBlocked(lang, ident) != true else { return nil }
            let word = path.word ?? lexicon?.wordID(ident: ident)
            let lmWord = validWord(word)
            // SPEC 8.5 rule 2: an invalid base variant isn't a word, so it's only ever the literal (or one Moe knows).
            let isWord = word == nil || lmWord != nil || personal?.isKnown(lang, ident) == true
            guard ident == literalIdent || isWord else { return nil }
            let corrected = personal?.hasCorrection(lang, typed: literalIdent, chosen: ident, rejected: false) == true
            return Suggestion(
                text: display(ident, word), ident: ident, isLiteral: ident == literalIdent,
                lm: lmLogProb(ident, word: lmWord, context), spatial: path.match.spatial, edits: path.match.edits,
                completion: path.match.completion,
                boosts: Double(explicitChars.filter(ident.contains).count) * config.explicitCharBoost
                    + (corrected ? config.correctionBoost : 0))
        }
        if paths[literalIdent] == nil {
            results.append(Suggestion(text: literal, ident: literalIdent, isLiteral: true,
                                      lm: lmLogProb(literalIdent, word: validWord(lexicon?.wordID(ident: literalIdent)), context),
                                      spatial: 0, edits: 0, completion: 0, boosts: 0))
        }
        results += tokenCandidates(literal)
        return ranked(results)
    }

    /// Next words for an empty current word (SPEC 8.6): personal trigram and bigram continuations,
    /// base bigrams and unigram backoff, scored by the full LM. Never the previous word or <s>, and
    /// only valid base words or known personal words.
    public func predict(context: [String], limit: Int = 3) -> [Suggestion] {
        let context = lmContext(context)
        let previous = context.idents.last
        let candidates = predictionPool(context).compactMap { ident, word -> Suggestion? in
            guard ident != previous, ident != sentenceStart, personal?.isBlocked(lang, ident) != true else { return nil }
            let word = word ?? lexicon?.wordID(ident: ident)
            // A personal continuation that is still pending (a one-off typo) isn't a word yet.
            guard validWord(word) != nil || personal?.isKnown(lang, ident) == true else { return nil }
            return Suggestion(text: display(ident, word), ident: ident, isLiteral: false, lm: lmLogProb(ident, word: word, context),
                              spatial: 0, edits: 0, completion: 0, boosts: 0)
        }
        return Array(ranked(candidates).prefix(limit))
    }

    // MARK: Helpers

    /// Beam search over the base and the personal trie, merged by ident: the cheapest path to each
    /// word, with its base word id when the base trie has it.
    private func searchBothTries(_ taps: [SearchTap], literalLength: Int) -> [String: (match: KeyMatch, word: Int?)] {
        var paths: [String: (match: KeyMatch, word: Int?)] = [:]
        func keep(_ ident: String, _ match: KeyMatch, _ word: Int?) {
            let known = paths[ident]
            if let known, known.match.cost <= match.cost { return }
            paths[ident] = (match, word ?? known?.word)
        }
        if let lexicon {
            for match in search(taps, literalLength: literalLength, in: lexicon) {
                for word in lexicon.variants(ofKey: match.key) { keep(lexicon.surface(word), match, word) }
            }
        }
        if let trie = personal?.trie(lang) {
            for match in search(taps, literalLength: literalLength, in: trie) {
                for ident in trie.idents(ofKey: match.key) { keep(ident, match, nil) }
            }
        }
        return paths
    }

    /// Prediction candidates: the top predictionPoolSize of each source, ident -> base word id when known.
    private func predictionPool(_ context: LMContext) -> [String: Int?] {
        let size = config.predictionPoolSize
        var pool: [String: Int?] = [:]
        func top(_ counts: [String: Double]) -> [String] { counts.sorted { $0.value > $1.value }.prefix(size).map(\.key) }
        for ident in top(context.personal.trigram) + top(context.personal.bigram) { pool[ident] = .some(nil) }
        if let trie = personal?.trie(lang) {
            for key in topKeys(size, in: trie) { trie.idents(ofKey: key).forEach { pool[$0] = .some(nil) } }
        }
        if let lexicon {
            let bigrams = context.previous.map { Array(lexicon.bigrams(after: $0).prefix(size)) } ?? []
            for word in bigrams + topKeys(size, in: lexicon).flatMap(lexicon.variants(ofKey:)) where lexicon.isValid(word) {
                pool[lexicon.surface(word)] = word
            }
        }
        return pool
    }

    /// The base word id when it's a valid word; an invalid variant scores as unknown (SPEC 8.2).
    func validWord(_ word: Int?) -> Int? {
        guard let lexicon, let word, lexicon.isValid(word) else { return nil }
        return word
    }

    func ranked(_ suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.sorted { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }
    }

    /// Normalized search taps, plus the typed non-normalized chars (SPEC 8.1, e.g. a long-pressed hamza).
    private func searchTaps(_ input: [Tap]) -> ([SearchTap], Set<String>) {
        var taps: [SearchTap] = []
        var explicitChars: Set<String> = []
        for tap in input {
            let key = normalize(tap.char, lang: lang)
            if key != tap.char.lowercased() { explicitChars.insert(tap.char) }
            taps += key.utf16.map { SearchTap(unit: $0, point: tap.point) }  // empty key: skipped at zero cost
        }
        return (taps, explicitChars)
    }

    /// Display form (SPEC 6.3): Moe's casing, then the corpus casing table, then the surface.
    private func display(_ ident: String, _ word: Int?) -> String {
        if let mine = personal?.display(lang, ident) { return mine }
        guard let lexicon, let word else { return ident }
        return lexicon.casing(word) ?? lexicon.surface(word)
    }

    /// Special tokens Moe uses (emails, handles), suggested by prefix once the literal looks like one.
    private func tokenCandidates(_ literal: String) -> [Suggestion] {
        guard literal.contains(where: { "@#./:".contains($0) }), let personal else { return [] }
        return personal.tokens(withPrefix: literal).filter { $0.display != literal }.map {
            Suggestion(text: $0.display, ident: $0.display, isLiteral: false, lm: 0, spatial: 0, edits: 0,
                       completion: config.completionPenalty, boosts: 0)
        }
    }
}
