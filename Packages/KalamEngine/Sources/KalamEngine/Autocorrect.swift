import Foundation

/// What the autocorrect policy needs beyond the candidates. Engine.autocorrection gathers it.
struct AutocorrectFacts {
    var lang: Lang
    var mode: AutocorrectMode
    var variantFix: Bool  // the setting for this language (EN contractions, AR variants)
    var traits: FieldTraits
    var literalValid: Bool  // a valid base variant
    var literalKnown: Bool  // a known personal word: never corrected
    var keptCount: Int  // times Moe kept the literal as typed
    var bestRejected: Bool  // Moe undid literal -> best before
}

/// SPEC 8.5: the candidate that replaces the typed literal on commit, or nil to keep it.
/// `ranked` is every candidate, best first, including the literal.
func autocorrectTarget(literal: String, ranked: [Suggestion], facts: AutocorrectFacts, config: EngineConfig) -> Suggestion? {
    let lang = facts.lang
    guard let best = ranked.first, !best.isLiteral, let typed = ranked.first(where: \.isLiteral),
          facts.mode != .off, facts.traits.allowsAutocorrect,  // rule 1
          !facts.literalKnown,  // rule 2, personal half
          !isSpecial(literal), !isSpecial(best.text), !literal.contains(where: \.isNumber),  // rule 3
          !(lang == .en && literal.count >= 2 && literal.contains(where: \.isLetter) && literal == literal.uppercased()),
          !facts.bestRejected  // rule 4
    else { return nil }
    if normalize(literal, lang: lang) == normalize(best.ident, lang: lang) {
        // Variant fix: replaces rule 2 for spellings of one key, valid or not (D8 keeps AR variants off).
        guard facts.variantFix, exp(best.lm) >= config.variantFixRatio * exp(typed.lm), facts.keptCount < config.variantFixMaxKept
        else { return nil }
    } else if facts.literalValid {
        return nil  // rule 2, base half
    }
    let threshold = facts.mode == .gentle ? config.autocorrectThresholdGentle : config.autocorrectThresholdNormal
    let share = 1 / ranked.reduce(0) { $0 + exp($1.score - best.score) }  // softmax share of best
    return best.score - typed.score >= threshold && share >= config.autocorrectMinShare ? best : nil  // rule 5
}

extension Engine {
    /// The autocorrect for a commit (SPEC 8.5), from the request's full candidate list.
    public func autocorrection(_ input: InputState, ranked: [Suggestion], traits: FieldTraits, settings: Settings) -> Suggestion? {
        let literal = input.literal
        let literalIdent = ident(literal, kind: kind)
        guard let best = ranked.first else { return nil }
        let sameKey = normalize(best.ident, lang: lang) == normalize(literalIdent, lang: lang)
        let facts = AutocorrectFacts(
            lang: lang, mode: settings.autocorrect(lang), variantFix: settings.variantFix(lang), traits: traits,
            literalValid: isValidBaseWord(literalIdent),
            literalKnown: personal?.isKnown(lang, literalIdent) ?? false,
            keptCount: sameKey && !best.isLiteral ? personal?.uses(lang, literalIdent) ?? 0 : 0,
            bestRejected: personal?.hasCorrection(lang, typed: literalIdent, chosen: best.ident, rejected: true) ?? false)
        return autocorrectTarget(literal: literal, ranked: ranked, facts: facts, config: config)
    }
}
