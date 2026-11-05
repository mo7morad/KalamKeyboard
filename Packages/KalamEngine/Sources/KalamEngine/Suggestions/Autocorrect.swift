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
    var inToken = false  // the literal ends a URL, path, domain, email or emoji run (rule 3)
    var sentenceStart = true  // the context is a sentence start
    var postCorrection = false  // re-scoring a committed word with the next word as right context
    /// The literal's raw uses + imports, and whether corrections holds it as a typo (rule 2). Called
    /// only for a correction about to happen, since it reads the store.
    var usage: () -> (uses: Int, recordedTypo: Bool) = { (0, false) }
}

/// D8: lazy spellings that are common words too, so the variant fix never applies them (its -> it's).
let ambiguousContractions: Set<String> = ["its", "were", "ill", "well", "hell", "id", "shell", "wed", "shed", "lets"]

/// SPEC 8.5: the candidate that replaces the typed literal on commit, or nil to keep it.
/// `ranked` is every candidate, best first, including the literal.
func autocorrectTarget(literal: String, ranked: [Suggestion], facts: AutocorrectFacts, config: EngineConfig) -> Suggestion? {
    let lang = facts.lang
    guard let best = ranked.first, !best.isLiteral, let typed = ranked.first(where: \.isLiteral),
          facts.mode != .off, facts.traits.allowsAutocorrect,  // rule 1
          !facts.literalKnown,  // rule 2, personal half
          !facts.inToken, !isSpecial(literal), !isSpecial(best.text), !literal.contains(where: \.isNumber),  // rule 3
          !(lang == .en && literal.dropFirst().contains(where: \.isUppercase)),  // OMG, LLMs, iOS, PhD
          !isMixedScript(literal),
          !facts.bestRejected  // rule 4
    else { return nil }
    let typedKey = normalize(literal, lang: lang), bestKey = normalize(best.ident, lang: lang)
    let sameKey = typedKey == bestKey
    let addedLetters = bestKey.unicodeScalars.count - typedKey.unicodeScalars.count
    // Gentle fixes slips only: neighbour keys (spatial cost), plus edits up to one omission or swap.
    guard best.completion == 0 || addedLetters <= config.autocorrectMaxAddedLetters,  // goin -> going, not يحبيب -> يحبيبتي
          facts.mode != .gentle || best.edits <= config.gentleMaxEditCost,
          !facts.postCorrection || (best.completion == 0 && best.spatial + best.edits <= config.postCorrectionMaxCost)  // one cheap edit
    else { return nil }
    var realWordMargin = 0.0
    if sameKey {
        // Variant fix: replaces rule 2 for spellings of one key, valid or not (D8 keeps AR variants off).
        // Lazy spellings only: an apostrophe or hamza that normalization would drop or map was typed on purpose.
        let lazySpelling = typedKey == literal.lowercased()
        guard facts.variantFix, lazySpelling, !(lang == .en && ambiguousContractions.contains(typedKey)),
              exp(best.lm) >= config.variantFixRatio * exp(typed.lm), facts.keptCount < config.variantFixMaxKept
        else { return nil }
    } else {
        guard !(lang == .en && literal.first?.isUppercase == true && !facts.sentenceStart) else { return nil }  // rule 3: shift mid-sentence, a name
        if facts.literalValid {
            // Rule 2, base half: a real word changes only to a full word that wins by far (rhe -> the),
            // and never to the same stem with another suffix, which context can't tell apart (خيرك -> خيره).
            guard best.completion == 0, !(lang == .ar && tradesSuffix(typedKey, bestKey)) else { return nil }
            realWordMargin = config.realWordMargin(lang)
        }
    }
    // AR normal counts c*'s edit cost twice: in Moe's chats an extra tap, a far key or a swap is more often a dialect word than a slip.
    let normal = config.autocorrectThresholdNormal + (lang == .ar ? best.edits : 0)
    let short = (1...3).contains(typedKey.unicodeScalars.count) ? config.autocorrectShortWordMargin : 0
    let threshold = (facts.mode == .gentle ? config.autocorrectThresholdGentle : normal) + short + realWordMargin
    let share = 1 / ranked.reduce(0) { $0 + exp($1.score - best.score) }  // softmax share of best
    guard best.score - typed.score >= threshold, share >= config.autocorrectMinShare else { return nil }  // rule 5
    if !sameKey {
        let usage = facts.usage()  // rule 2: a word Moe used, unless it's a recorded typo
        if usage.uses >= config.protectMinUses, !usage.recordedTypo { return nil }
    }
    return best
}

/// AR: b is a's stem with another of the clitic suffixes (يهديها, يهدينا).
func tradesSuffix(_ a: String, _ b: String) -> Bool {
    arabicSuffixes.contains { s in
        a.hasSuffix(s) && arabicSuffixes.contains { t in t != s && b.hasSuffix(t) && a.dropLast(s.count) == b.dropLast(t.count) }
    }
}

/// Rule 3: a word with both Arabic-script and other letters.
func isMixedScript(_ word: String) -> Bool {
    let scripts = Set(word.unicodeScalars.compactMap(strongDirection))
    return scripts.count == 2
}

extension Engine {
    /// The autocorrect for a commit (SPEC 8.5), from the request's full candidate list.
    /// `inToken`: the keyboard's insideNonWordToken for the text before the literal.
    public func autocorrection(_ input: InputState, ranked: [Suggestion], traits: FieldTraits, settings: Settings,
                               inToken: Bool = false, postCorrection: Bool = false) -> Suggestion? {
        let literal = input.literal
        let literalIdent = ident(literal, kind: kind)
        guard let best = ranked.first else { return nil }
        let sameKey = normalize(best.ident, lang: lang) == normalize(literalIdent, lang: lang)
        let facts = AutocorrectFacts(
            lang: lang, mode: settings.autocorrect(lang), variantFix: settings.variantFix(lang), traits: traits,
            literalValid: isValidBaseWord(literalIdent) || isCliticForm(literalIdent),
            literalKnown: personal?.isKnown(lang, literalIdent) ?? false,
            keptCount: sameKey && !best.isLiteral ? personal?.uses(lang, literalIdent) ?? 0 : 0,
            bestRejected: personal?.hasCorrection(lang, typed: literalIdent, chosen: best.ident, rejected: true) ?? false,
            inToken: inToken, sentenceStart: input.context.last.map { $0 == sentenceStart } ?? true, postCorrection: postCorrection,
            usage: { [personal, lang] in personal?.usage(lang, literalIdent) ?? (0, false) })
        return autocorrectTarget(literal: literal, ranked: ranked, facts: facts, config: config)
    }

    /// A word rule 2 never corrects: a valid base word, a known personal word or an AR clitic form.
    public func isWord(_ ident: String) -> Bool {
        isValidBaseWord(ident) || personal?.isKnown(lang, ident) == true || isCliticForm(ident)
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
