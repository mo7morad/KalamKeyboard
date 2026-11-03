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
    public let text: String  // display form, after the corpus casing table
    public let ident: String
    public internal(set) var isLiteral: Bool
    public let lm: Double
    public let spatial: Double  // already weighted by alpha
    public let edits: Double
    public let completion: Double
    public let boosts: Double

    public var score: Double { lm - spatial - edits - completion + boosts }
}

public struct Engine {
    public let lang: Lang
    public let config: EngineConfig
    let lexicon: BaseLexicon?
    let spatial: SpatialModel

    /// A missing lexicon, or one for another language, leaves only the literal candidate.
    public init(lang: Lang, lexicon: BaseLexicon?, layout: Layout?, config: EngineConfig = EngineConfig()) {
        self.lang = lang
        self.lexicon = lexicon?.lang == lang ? lexicon : nil
        self.spatial = SpatialModel(layout: layout?.lang == lang ? layout : nil)
        self.config = config
    }

    public func suggest(_ input: InputState, limit: Int = 3) -> [Suggestion] {
        let literal = input.literal
        guard !literal.isEmpty else { return [] }
        let kind: Token.Kind = lang == .en ? .en : .ar
        let previous = lexicon?.wordID(ident: ident(input.context.last ?? sentenceStart, kind: kind))
        var byIdent = lexicon.map { baseCandidates(input.taps, literalLength: literal.count, after: previous, in: $0) } ?? [:]

        let literalIdent = ident(literal, kind: kind)
        if byIdent[literalIdent] != nil {
            byIdent[literalIdent]?.isLiteral = true
        } else {
            let lm = lexicon.flatMap { lex in lex.wordID(ident: literalIdent).map { lmLogProb($0, after: previous, in: lex) } }
            byIdent[literalIdent] = Suggestion(text: literal, ident: literalIdent, isLiteral: true, lm: lm ?? config.unknownLogProb,
                                        spatial: 0, edits: 0, completion: 0, boosts: 0)
        }
        let ranked = byIdent.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }
        return Array(ranked.prefix(limit))
    }

    /// Every variant of every key the beam search reaches, best score per ident.
    private func baseCandidates(_ input: [Tap], literalLength: Int, after previous: Int?, in lexicon: BaseLexicon) -> [String: Suggestion] {
        var taps: [SearchTap] = []
        var explicitChars: Set<String> = []  // SPEC 8.1: typed non-normalized chars, e.g. a long-pressed hamza
        for tap in input {
            let key = normalize(tap.char, lang: lang)
            if key != tap.char.lowercased() { explicitChars.insert(tap.char) }
            taps += key.utf16.map { SearchTap(unit: $0, point: tap.point) }  // empty key: skipped at zero cost
        }
        var byIdent: [String: Suggestion] = [:]
        for match in search(taps, literalLength: literalLength, in: lexicon) {
            for word in lexicon.variants(ofKey: match.key) {
                let surface = lexicon.surface(word)
                let candidate = Suggestion(
                    text: lexicon.casing(word) ?? surface, ident: surface, isLiteral: false,
                    lm: lmLogProb(word, after: previous, in: lexicon),
                    spatial: match.spatial, edits: match.edits, completion: match.completion,
                    boosts: Double(explicitChars.filter(surface.contains).count) * config.explicitCharBoost)
                if byIdent[surface].map({ $0.score < candidate.score }) ?? true { byIdent[surface] = candidate }
            }
        }
        return byIdent
    }

    /// Interpolated LM (SPEC 8.3) with base data only. The personal terms are 0 until Phase 4,
    /// which leaves P = bigramShare * PB(w|b) + (1 - bigramShare) * PB(w).
    func lmLogProb(_ word: Int, after previous: Int?, in lexicon: BaseLexicon) -> Double {
        let bigram = previous.flatMap { lexicon.bigramLogProb($0, word) }.map(exp) ?? 0
        let p = config.bigramShare * bigram + (1 - config.bigramShare) * exp(lexicon.logProb(word))
        return p > 0 ? log(p) : config.unknownLogProb
    }
}
