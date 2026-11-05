import Foundation

extension Engine {
    /// SPEC 8.5 post-correction: once the next word commits, the previous word, committed as typed,
    /// is re-scored with `next` as its right context (hell me -> help me). `input` is the
    /// previous word's taps and left context. Returns its replacement, or nil to keep it.
    public func postCorrection(_ input: InputState, next: String, traits: FieldTraits, settings: Settings,
                               inToken: Bool = false) -> Suggestion? {
        let next = ident(next, kind: kind)
        let word = validWord(lexicon?.wordID(ident: next))
        let all = candidates(input)
        let pool = all.prefix(config.postCorrectionPool) + all.dropFirst(config.postCorrectionPool).filter(\.isLiteral)
        let rescored = pool.map { c in
            let right = lmLogProb(next, word: word, lmContext(input.context.suffix(1) + [c.ident]))  // P(next | b, c)
            return Suggestion(text: c.text, ident: c.ident, isLiteral: c.isLiteral, lm: c.lm + right, spatial: c.spatial,
                              edits: c.edits, completion: c.completion, boosts: c.boosts)
        }
        return autocorrection(input, ranked: ranked(rescored), traits: traits, settings: settings, inToken: inToken, postCorrection: true)
    }
}
