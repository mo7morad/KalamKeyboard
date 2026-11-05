import Foundation
import Testing
@testable import KalamEngine

private func candidate(_ text: String, lm: Double, edits: Double = 0, completion: Double = 0, literal: Bool = false) -> Suggestion {
    Suggestion(text: text, ident: text.lowercased(), isLiteral: literal, lm: lm, spatial: 0, edits: edits, completion: completion, boosts: 0)
}

private let normalFacts = AutocorrectFacts(lang: .en, mode: .normal, variantFix: true, traits: FieldTraits(), literalValid: false,
                                           literalKnown: false, keptCount: 0, bestRejected: false)

struct PolicyCase: CustomTestStringConvertible, Sendable {
    let name: String
    let literal: String
    let best: String
    let bestLM: Double  // the literal's lm is -14 unless literalLM is set
    var literalLM = -14.0
    var bestEdits = 0.0
    var bestCompletion = 0.0
    var change: @Sendable (inout AutocorrectFacts) -> Void = { _ in }
    let corrects: Bool
    var testDescription: String { name }
}

private let cases: [PolicyCase] = [
    PolicyCase(name: "clear typo", literal: "teh", best: "the", bestLM: -4, corrects: true),
    PolicyCase(name: "known personal word is never corrected", literal: "teh", best: "the", bestLM: -4,
               change: { $0.literalKnown = true }, corrects: false),
    PolicyCase(name: "valid base word is kept", literal: "hell", best: "hello", bestLM: -4, change: { $0.literalValid = true }, corrects: false),
    PolicyCase(name: "rejected pair never repeats", literal: "teh", best: "the", bestLM: -4, change: { $0.bestRejected = true }, corrects: false),
    PolicyCase(name: "normal threshold met", literal: "teh", best: "the", bestLM: -11, corrects: true),
    PolicyCase(name: "gentle threshold missed", literal: "teh", best: "the", bestLM: -11, change: { $0.mode = .gentle }, corrects: false),
    PolicyCase(name: "gentle threshold met", literal: "teh", best: "the", bestLM: -9, change: { $0.mode = .gentle }, corrects: true),
    PolicyCase(name: "gentle fixes one omission", literal: "hllo", best: "hello", bestLM: -4, bestEdits: 3,
               change: { $0.mode = .gentle }, corrects: true),
    PolicyCase(name: "gentle skips an extra-tap or far-key fix", literal: "hellp", best: "hell", bestLM: -4, bestEdits: 5,
               change: { $0.mode = .gentle }, corrects: false),
    PolicyCase(name: "completion one letter past the taps", literal: "goin", best: "going", bestLM: -4, bestCompletion: 1, corrects: true),
    PolicyCase(name: "completion two letters past the taps", literal: "goi", best: "going", bestLM: -4, bestCompletion: 1, corrects: false),
    PolicyCase(name: "below normal threshold", literal: "teh", best: "the", bestLM: -13.5, corrects: false),
    PolicyCase(name: "AR normal fixes a slip by a small margin", literal: "مايون", best: "مليون", bestLM: -12.5,
               change: { $0.lang = .ar }, corrects: true),
    PolicyCase(name: "AR normal counts an edit twice", literal: "عاوزينا", best: "عاوزين", bestLM: -6, bestEdits: 5,
               change: { $0.lang = .ar }, corrects: false),
    PolicyCase(name: "AR normal fixes an edit by a clear margin", literal: "اموورك", best: "امورك", bestLM: -2.5, bestEdits: 5,
               change: { $0.lang = .ar }, corrects: true),
    PolicyCase(name: "EN contraction fix", literal: "dont", best: "don't", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true }, corrects: true),
    PolicyCase(name: "contraction fix off", literal: "dont", best: "don't", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true; $0.variantFix = false }, corrects: false),
    PolicyCase(name: "variant kept twice", literal: "dont", best: "don't", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true; $0.keptCount = 2 }, corrects: false),
    PolicyCase(name: "variant ratio under 5", literal: "dont", best: "don't", bestLM: -6, literalLM: -7,
               change: { $0.literalValid = true }, corrects: false),
    PolicyCase(name: "typed apostrophe is never variant-fixed", literal: "week's", best: "weeks", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true }, corrects: false),
    PolicyCase(name: "AR variant fix off by default", literal: "انا", best: "أنا", bestLM: -3, literalLM: -9,
               change: { $0.lang = .ar; $0.literalValid = true; $0.mode = .gentle; $0.variantFix = Settings().arabicVariantFix }, corrects: false),
    PolicyCase(name: "AR variant fix when turned on", literal: "انا", best: "أنا", bestLM: -3, literalLM: -9,
               change: { $0.lang = .ar; $0.literalValid = true; $0.mode = .gentle }, corrects: true),
    PolicyCase(name: "digits", literal: "3ashan", best: "washan", bestLM: -4, corrects: false),
    PolicyCase(name: "handle", literal: "@moe", best: "moe", bestLM: -4, corrects: false),
    PolicyCase(name: "never into a special token", literal: "mee", best: "me@x.com", bestLM: -4, corrects: false),
    PolicyCase(name: "EN all caps", literal: "OMG", best: "omg", bestLM: -4, corrects: false),
    PolicyCase(name: "EN capital after the first letter", literal: "LLMs", best: "looks", bestLM: -4, corrects: false),
    PolicyCase(name: "autocorrect off", literal: "teh", best: "the", bestLM: -4, change: { $0.mode = .off }, corrects: false),
    PolicyCase(name: "field without autocorrection", literal: "teh", best: "the", bestLM: -4,
               change: { $0.traits.autocorrection = false }, corrects: false),
    PolicyCase(name: "URL field", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.keyboardType = .url }, corrects: false),
    PolicyCase(name: "email field", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.keyboardType = .email }, corrects: false),
    PolicyCase(name: "password field", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.contentType = .password }, corrects: false),
    PolicyCase(name: "one-time code", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.contentType = .oneTimeCode }, corrects: false),
    // Rule 2: words Moe used, typed or imported.
    PolicyCase(name: "word used twice is kept", literal: "tgem", best: "them", bestLM: -4, change: { $0.usage = { (2, false) } }, corrects: false),
    PolicyCase(name: "word used once is corrected", literal: "tgem", best: "them", bestLM: -4, change: { $0.usage = { (1, false) } }, corrects: true),
    PolicyCase(name: "word used twice but a recorded typo is corrected", literal: "tgem", best: "them", bestLM: -4,
               change: { $0.usage = { (2, true) } }, corrects: true),
    PolicyCase(name: "variant fix keeps its own kept rule", literal: "dont", best: "don't", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true; $0.usage = { (5, false) } }, corrects: true),
    // Rule 3 guards.
    PolicyCase(name: "inside a URL, path, domain or email", literal: "goo", best: "good", bestLM: -4, bestCompletion: 1,
               change: { $0.inToken = true }, corrects: false),
    PolicyCase(name: "mixed script", literal: "helloمر", best: "hello", bestLM: -4, corrects: false),
    PolicyCase(name: "capital at a sentence start", literal: "Tgem", best: "Them", bestLM: -4, corrects: true),
    PolicyCase(name: "mid-sentence capital is a name", literal: "Tgem", best: "Them", bestLM: -4,
               change: { $0.sentenceStart = false }, corrects: false),
    PolicyCase(name: "mid-sentence capital still gets the contraction fix", literal: "Im", best: "I'm", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true; $0.sentenceStart = false }, corrects: true),
    PolicyCase(name: "AR has no capitals rule", literal: "مايون", best: "مليون", bestLM: -12.5,
               change: { $0.lang = .ar; $0.sentenceStart = false }, corrects: true),
    PolicyCase(name: "short word needs the extra margin", literal: "teh", best: "the", bestLM: -12.5, corrects: false),
    PolicyCase(name: "four letters get the normal threshold", literal: "tgem", best: "them", bestLM: -12.5, corrects: true),
    // D8: lazy spellings that are words too stay suggestions.
    PolicyCase(name: "its stays", literal: "its", best: "it's", bestLM: -6, literalLM: -9.9, change: { $0.literalValid = true }, corrects: false),
    PolicyCase(name: "Were stays", literal: "Were", best: "We're", bestLM: -6, literalLM: -9.9, change: { $0.literalValid = true }, corrects: false),
    PolicyCase(name: "im still fixes", literal: "im", best: "I'm", bestLM: -6, literalLM: -9.9, change: { $0.literalValid = true }, corrects: true),
]

@Test(arguments: cases)
func autocorrectPolicy(_ c: PolicyCase) {
    var facts = normalFacts
    c.change(&facts)
    let ranked = [candidate(c.best, lm: c.bestLM, edits: c.bestEdits, completion: c.bestCompletion), candidate(c.literal, lm: c.literalLM, literal: true)]
    let result = autocorrectTarget(literal: c.literal, ranked: ranked, facts: facts, config: EngineConfig())
    #expect((result?.text == c.best) == c.corrects)
}

private let contractions = ["its": "it's", "were": "we're", "ill": "I'll", "well": "we'll", "hell": "he'll", "id": "I'd",
                            "shell": "she'll", "wed": "we'd", "shed": "she'd", "lets": "let's"]

@Test(arguments: contractions.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
func ambiguousContractionIsNeverAutoApplied(_ word: String, _ contraction: String) {
    let ranked = [candidate(contraction, lm: -3), candidate(word, lm: -12, literal: true)]
    var facts = normalFacts
    facts.literalValid = true
    #expect(autocorrectTarget(literal: word, ranked: ranked, facts: facts, config: EngineConfig()) == nil)
}

@Test func usageIsReadOnlyForACorrectionAboutToHappen() {
    var facts = normalFacts
    facts.usage = {
        Issue.record("store read for a commit that keeps the literal")
        return (0, false)
    }
    let ranked = [candidate("them", lm: -13.5), candidate("tgem", lm: -14, literal: true)]
    #expect(autocorrectTarget(literal: "tgem", ranked: ranked, facts: facts, config: EngineConfig()) == nil)
}

@Test func lowSoftmaxShareKeepsTheLiteral() {
    let ranked = [candidate("the", lm: -4), candidate("tea", lm: -4.1), candidate("ten", lm: -4.2), candidate("teh", lm: -14, literal: true)]
    #expect(autocorrectTarget(literal: "teh", ranked: ranked, facts: normalFacts, config: EngineConfig()) == nil)
}

@Test func literalOnTopIsKept() {
    let ranked = [candidate("teh", lm: -2, literal: true), candidate("the", lm: -4)]
    #expect(autocorrectTarget(literal: "teh", ranked: ranked, facts: normalFacts, config: EngineConfig()) == nil)
}

@Test(arguments: [("teh", "the"), ("dont", "don't"), ("im", "i'm")])
func engineAutocorrectsWithDefaultSettings(_ typed: String, _ expected: String) throws {
    let engine = try fixtureEngine(.en)
    let input = InputState(context: [], taps: taps(typed))
    let result = engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings())
    #expect(result?.ident == expected)
}

@Test(arguments: [("Teh", [sentenceStart], "the"), ("Teh", ["see"], nil), ("Im", ["see"], "i'm")] as [(String, [String], String?)])
func engineLeavesMidSentenceCapitals(_ typed: String, _ context: [String], _ expected: String?) throws {
    let engine = try fixtureEngine(.en)
    let input = InputState(context: context, taps: taps(typed))
    #expect(engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings())?.ident == expected)
}

@Test func engineKeepsTheLiteralInsideAToken() throws {
    let engine = try fixtureEngine(.en)
    let input = InputState(context: [], taps: taps("teh"))
    #expect(engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings(), inToken: true) == nil)
}

/// "teh" typed twice in one session: pending, but used twice. A recorded typo of "the" is corrected anyway.
@Test(arguments: [false, true])
func engineNeverCorrectsAWordUsedTwice(_ recordedTypo: Bool) throws {
    let engine = try personalEngine(.en, []) {
        for _ in 0..<2 { $0.addWord("teh", kind: .en, context: [], at: 0, source: .typed, session: 1) }
        if recordedTypo { $0.addCorrection(lang: "en", typed: "teh", chosen: "the", rejected: false, at: 0) }
    }
    #expect(engine.personal?.isKnown(.en, "teh") == false)
    let input = InputState(context: [], taps: taps("teh"))
    #expect(engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings())?.ident
        == (recordedTypo ? "the" : nil))
}

@Test func engineNeverCorrectsAPersonalWord() throws {
    let engine = try personalEngine(.en, ["teh teh"])
    let input = InputState(context: [], taps: taps("teh"))
    #expect(engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings()) == nil)
}

@Test(arguments: [("ومن", "من"), ("يحبيبي", "حبيبي"), ("عايزش", "عايز")])
func arabicKnownWordPlusACliticIsKept(_ typed: String, _ stem: String) throws {
    let engine = try fixtureEngine(.ar)
    var settings = Settings()
    settings.autocorrectAR = .normal
    let input = InputState(context: [], taps: typed.map { Tap(String($0)) })
    let ranked = engine.candidates(input)
    #expect(ranked.first?.ident == stem)
    #expect(engine.autocorrection(input, ranked: ranked, traits: FieldTraits(), settings: settings) == nil)
}

// م + عايز + ش, شكرا + لك, عايز + وا; مدهش (م + ده + ش) has a stem under 3 letters
@Test(arguments: [("معايزش", true), ("شكرالك", true), ("عايزوا", true), ("معايز", false), ("مدهش", false)])
func arabicCliticForms(_ ident: String, _ isClitic: Bool) throws {
    #expect(try fixtureEngine(.ar).isCliticForm(ident) == isClitic)
}

// base word, known personal word (seen twice), clitic form, a typo seen once, a non-word
@Test(arguments: [("عايز", true), ("بنجرب", true), ("وعايز", true), ("بنحرب", false), ("ععع", false)])
func arabicWordsRuleTwoNeverCorrects(_ ident: String, _ isWord: Bool) throws {
    #expect(try personalEngine(.ar, ["بنجرب", "بنجرب", "بنحرب"]).isWord(ident) == isWord)
}
