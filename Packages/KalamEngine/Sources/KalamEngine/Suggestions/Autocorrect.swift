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
          !(lang == .en && literal.dropFirst().contains(where: \.isUppercase)),  // OMG, LLMs, iOS, PhD
          !facts.bestRejected  // rule 4
    else { return nil }
    let typedKey = normalize(literal, lang: lang), bestKey = normalize(best.ident, lang: lang)
    let addedLetters = bestKey.unicodeScalars.count - typedKey.unicodeScalars.count
    // Gentle fixes slips only: neighbour keys (spatial cost), plus edits up to one omission or swap.
    guard best.completion == 0 || addedLetters <= config.autocorrectMaxAddedLetters,  // goin -> going, not يحبيب -> يحبيبتي
          facts.mode != .gentle || best.edits <= config.gentleMaxEditCost
    else { return nil }
    if typedKey == bestKey {
        // Variant fix: replaces rule 2 for spellings of one key, valid or not (D8 keeps AR variants off).
        // Lazy spellings only: an apostrophe or hamza that normalization would drop or map was typed on purpose.
        let lazySpelling = typedKey == literal.lowercased()
        guard facts.variantFix, lazySpelling, exp(best.lm) >= config.variantFixRatio * exp(typed.lm), facts.keptCount < config.variantFixMaxKept
        else { return nil }
    } else if facts.literalValid {
        return nil  // rule 2, base half
    }
    // AR normal counts c*'s edit cost twice: in Moe's chats an extra tap, a far key or a swap is more often a dialect word than a slip.
    let normal = config.autocorrectThresholdNormal + (lang == .ar ? best.edits : 0)
    let threshold = facts.mode == .gentle ? config.autocorrectThresholdGentle : normal
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
            literalValid: isValidBaseWord(literalIdent) || isCliticForm(literalIdent),
            literalKnown: personal?.isKnown(lang, literalIdent) ?? false,
            keptCount: sameKey && !best.isLiteral ? personal?.uses(lang, literalIdent) ?? 0 : 0,
            bestRejected: personal?.hasCorrection(lang, typed: literalIdent, chosen: best.ident, rejected: true) ?? false)
        return autocorrectTarget(literal: literal, ranked: ranked, facts: facts, config: config)
    }

    /// AR rule 2: a known word plus one clitic (بكلم, افتكره) counts as a word too.
    func isCliticForm(_ ident: String) -> Bool {
        guard lang == .ar else { return false }
        func known(_ stem: Substring) -> Bool {
            stem.count >= 2 && (isValidBaseWord(String(stem)) || personal?.isKnown(lang, String(stem)) == true)
        }
        return arabicPrefixes.contains { ident.hasPrefix($0) && known(ident.dropFirst($0.count)) }
            || arabicSuffixes.contains { ident.hasSuffix($0) && known(ident.dropLast($0.count)) }
            || ident.count >= 5 && ident.hasPrefix("م") && ident.hasSuffix("ش") && known(ident.dropFirst().dropLast())  // negation م…ش
    }
}

// لل: ل + ال, which drops its alif. ي: a fused يا (يحبيبتي).
private let arabicPrefixes = ["و", "ف", "ب", "ل", "ك", "ه", "ح", "ال", "لل", "ي"]
// ش: negation (مخلصش); لي … لنا: "to me" … "to us" (قولتلي); وا: plural (بيعملوا).
private let arabicSuffixes = ["ه", "ها", "هم", "ك", "كم", "ني", "نا", "ي", "ش", "لي", "له", "لك", "لها", "لهم", "لنا", "وا"]
