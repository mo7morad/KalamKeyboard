import Foundation
import Testing
@testable import KalamEngine

private func candidate(_ text: String, lm: Double, cost: Double = 0, literal: Bool = false) -> Suggestion {
    Suggestion(text: text, ident: text.lowercased(), isLiteral: literal, lm: lm, spatial: cost, edits: 0, completion: 0, boosts: 0)
}

private let normalFacts = AutocorrectFacts(lang: .en, mode: .normal, variantFix: true, traits: FieldTraits(), literalValid: false,
                                           literalKnown: false, keptCount: 0, bestRejected: false)

struct PolicyCase: CustomTestStringConvertible, Sendable {
    let name: String
    let literal: String
    let best: String
    let bestLM: Double  // the literal's lm is -14 unless literalLM is set
    var literalLM = -14.0
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
    PolicyCase(name: "below normal threshold", literal: "teh", best: "the", bestLM: -12, corrects: false),
    PolicyCase(name: "EN contraction fix", literal: "dont", best: "don't", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true }, corrects: true),
    PolicyCase(name: "contraction fix off", literal: "dont", best: "don't", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true; $0.variantFix = false }, corrects: false),
    PolicyCase(name: "variant kept twice", literal: "dont", best: "don't", bestLM: -6, literalLM: -9.9,
               change: { $0.literalValid = true; $0.keptCount = 2 }, corrects: false),
    PolicyCase(name: "variant ratio under 5", literal: "dont", best: "don't", bestLM: -6, literalLM: -7,
               change: { $0.literalValid = true }, corrects: false),
    PolicyCase(name: "AR variant fix off by default", literal: "انا", best: "أنا", bestLM: -3, literalLM: -9,
               change: { $0.lang = .ar; $0.literalValid = true; $0.mode = .gentle; $0.variantFix = Settings().arabicVariantFix }, corrects: false),
    PolicyCase(name: "AR variant fix when turned on", literal: "انا", best: "أنا", bestLM: -3, literalLM: -9,
               change: { $0.lang = .ar; $0.literalValid = true; $0.mode = .gentle }, corrects: true),
    PolicyCase(name: "digits", literal: "3ashan", best: "washan", bestLM: -4, corrects: false),
    PolicyCase(name: "handle", literal: "@moe", best: "moe", bestLM: -4, corrects: false),
    PolicyCase(name: "never into a special token", literal: "mee", best: "me@x.com", bestLM: -4, corrects: false),
    PolicyCase(name: "EN all caps", literal: "OMG", best: "omg", bestLM: -4, corrects: false),
    PolicyCase(name: "autocorrect off", literal: "teh", best: "the", bestLM: -4, change: { $0.mode = .off }, corrects: false),
    PolicyCase(name: "field without autocorrection", literal: "teh", best: "the", bestLM: -4,
               change: { $0.traits.autocorrection = false }, corrects: false),
    PolicyCase(name: "URL field", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.keyboardType = .url }, corrects: false),
    PolicyCase(name: "email field", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.keyboardType = .email }, corrects: false),
    PolicyCase(name: "password field", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.contentType = .password }, corrects: false),
    PolicyCase(name: "one-time code", literal: "teh", best: "the", bestLM: -4, change: { $0.traits.contentType = .oneTimeCode }, corrects: false),
]

@Test(arguments: cases)
func autocorrectPolicy(_ c: PolicyCase) {
    var facts = normalFacts
    c.change(&facts)
    let ranked = [candidate(c.best, lm: c.bestLM), candidate(c.literal, lm: c.literalLM, literal: true)]
    let result = autocorrectTarget(literal: c.literal, ranked: ranked, facts: facts, config: EngineConfig())
    #expect((result?.text == c.best) == c.corrects)
}

@Test func lowSoftmaxShareKeepsTheLiteral() {
    let ranked = [candidate("the", lm: -4), candidate("tea", lm: -4.1), candidate("ten", lm: -4.2), candidate("teh", lm: -14, literal: true)]
    #expect(autocorrectTarget(literal: "teh", ranked: ranked, facts: normalFacts, config: EngineConfig()) == nil)
}

@Test func literalOnTopIsKept() {
    let ranked = [candidate("teh", lm: -2, literal: true), candidate("the", lm: -4)]
    #expect(autocorrectTarget(literal: "teh", ranked: ranked, facts: normalFacts, config: EngineConfig()) == nil)
}

@Test(arguments: [("teh", "the"), ("dont", "don't")])
func engineAutocorrectsWithDefaultSettings(_ typed: String, _ expected: String) throws {
    let engine = try fixtureEngine(.en)
    let input = InputState(context: [], taps: taps(typed))
    let result = engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings())
    #expect(result?.ident == expected)
}

@Test func engineNeverCorrectsAPersonalWord() throws {
    let engine = try personalEngine(.en, ["teh teh"])
    let input = InputState(context: [], taps: taps("teh"))
    #expect(engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings()) == nil)
}
