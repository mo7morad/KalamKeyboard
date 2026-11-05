import Testing
@testable import KalamEngine

@Test(arguments: [
    ("rhe", "the"),  // spatial: r is next to t
    ("teh", "the"),  // transposition
    ("helo", "hello"),  // doubled-letter omission
    ("leter", "letter"),  // doubled-letter omission
])
func correctsTypo(_ typed: String, _ expected: String) throws {
    #expect(suggestions(try fixtureEngine(.en), typed).first == expected)
}

@Test func aKeyTappedTwiceCostsLessThanAnExtraTap() throws {
    let engine = try fixtureEngine(.en)
    func edits(_ typed: String) -> Double? { engine.candidates(InputState(context: [], taps: taps(typed))).first { $0.ident == "wait" }?.edits }
    #expect(edits("waait") == EngineConfig().doubledInsertionCost)
    #expect(edits("wapit") == EngineConfig().insertionCost)
}

@Test func completesPrefix() throws {
    let top = suggestions(try fixtureEngine(.en), "hel")
    #expect(top.contains("hello") && top.contains("help"))
}

@Test func arabicVariantIsSuggested() throws {
    let top = suggestions(try fixtureEngine(.ar), "انا")
    #expect(top.contains("انا") && top.contains("أنا"))
}

@Test func literalIsAlwaysACandidate() throws {
    let results = try fixtureEngine(.en).suggest(InputState(context: [], taps: taps("qzx")), limit: 10)
    let literal = try #require(results.first { $0.isLiteral })
    #expect((literal.text, literal.lm) == ("qzx", EngineConfig().unknownLogProb(.en)))
}

@Test func invalidBaseVariantIsOnlyEverTheUnknownLiteral() throws {
    let engine = try fixtureEngine(.en)
    let typed = try #require(engine.suggest(InputState(context: [], taps: taps("alot")), limit: 10).first { $0.isLiteral })
    #expect(typed.lm == EngineConfig().unknownLogProb(.en))
    #expect(!suggestions(engine, "alo", limit: 10).contains("alot"))
}

@Test func generatedFormIsACandidateButNotAWord() throws {
    let engine = try fixtureEngine(.ar)
    #expect(suggestions(engine, "مبيعرفس", limit: 10).contains("مبيعرفش"))
    #expect(!engine.isWord("مبيعرفش"))  // so a typo that happens to be a generated form still corrects
}

@Test func knownLiteralMergesWithItsWord() throws {
    let results = try fixtureEngine(.en).suggest(InputState(context: [], taps: taps("the")), limit: 10)
    let first = try #require(results.first)
    #expect(first.text == "the" && first.isLiteral)
    #expect(results.filter { $0.ident == "the" }.count == 1)
}

@Test func bigramContextChangesRanking() throws {
    let engine = try fixtureEngine(.en)
    #expect(suggestions(engine, "yo", context: ["see"]).first == "you")
    let afterSee = engine.suggest(InputState(context: ["see"], taps: taps("you")), limit: 1)[0].lm
    let atStart = engine.suggest(InputState(context: [], taps: taps("you")), limit: 1)[0].lm
    #expect(afterSee > atStart)
}

@Test func curlyApostropheContextReachesTheBigram() throws {
    let engine = try fixtureEngine(.en)
    let curly = engine.suggest(InputState(context: ["don’t"], taps: taps("wait")), limit: 1)[0].lm
    let straight = engine.suggest(InputState(context: ["don't"], taps: taps("wait")), limit: 1)[0].lm
    let none = engine.suggest(InputState(context: [], taps: taps("wait")), limit: 1)[0].lm
    #expect(curly == straight && curly > none)
}

@Test func tapOnKeyMissingFromThePageStillMatchesItsChar() throws {
    let lexicon = try #require(BaseLexicon(data: fixtureData(.en)))
    let engine = Engine(lang: .en, lexicon: lexicon, layout: nil)
    let tapsWithPoints = "the".map { Tap(String($0), at: Point(x: 0, y: 0)) }
    let the = try #require(engine.suggest(InputState(context: [], taps: tapsWithPoints), limit: 5).first { $0.ident == "the" })
    #expect(the.spatial == 0 && the.edits == 0)
}

@Test func casingTableAppliesToDisplay() throws {
    #expect(suggestions(try fixtureEngine(.en), "i", limit: 1) == ["I"])
}

@Test func typedApostropheBoostsTheContraction() throws {
    let results = try fixtureEngine(.en).suggest(InputState(context: [], taps: taps("don't")), limit: 5)
    let dont = try #require(results.first { $0.ident == "don't" })
    #expect(dont.boosts == EngineConfig().explicitCharBoost)
    #expect(results.first?.ident == "don't")
}

@Test func pointlessTapsMatchExactlyOrPayFarSubstitution() throws {
    let engine = try fixtureEngine(.en)
    let exact = engine.suggest(InputState(context: [], taps: "letter".map { Tap(String($0)) }), limit: 1)[0]
    #expect((exact.text, exact.spatial, exact.edits) == ("letter", 0, 0))
    let far = engine.suggest(InputState(context: [], taps: "lettar".map { Tap(String($0)) }), limit: 5)
    #expect(far.first { $0.text == "letter" }?.edits == EngineConfig().farSubstitutionCost)
}

@Test func missingLexiconGivesLiteralOnly() {
    let engine = Engine(lang: .en, lexicon: nil, layout: Layout.bundled("en-letters"))
    let results = engine.suggest(InputState(context: [], taps: taps("the")), limit: 5)
    #expect(results.map(\.text) == ["the"] && results[0].isLiteral)
}

@Test func lexiconForAnotherLanguageIsIgnored() throws {
    let arabic = try #require(BaseLexicon(data: fixtureData(.ar)))
    let engine = Engine(lang: .en, lexicon: arabic, layout: nil)
    #expect(engine.suggest(InputState(context: [], taps: taps("the")), limit: 5).count == 1)
}

@Test func configSetsConstantsByName() {
    var config = EngineConfig()
    let results = [config.set("sigma", "0.6"), config.set("beamWidth", "32"), config.set("nope", "1"), config.set("beamWidth", "x")]
    #expect(results == [true, true, false, false])
    #expect(config.sigma == 0.6 && config.beamWidth == 32)
}

/// SPEC 8.2: ة/ه, ى/ي and أ/إ/آ/ا share a normalized key, so the other spelling costs only what
/// the taps themselves cost (each tap at a key center pays the fixed tap offset): no edit. The ة and
/// ى keys count as ه and ي keys. (ؤ and ئ map to و and ي, so مسؤول / مسئول are one edit apart.)
@Test(arguments: [("مدرسه", "مدرسة"), ("علي", "على"), ("على", "علي"), ("انا", "أنا"), ("الي", "إلى")])
func arabicVariantsCostNothingInTheBeam(_ typed: String, _ variant: String) throws {
    let config = EngineConfig()
    let input = InputState(context: [], taps: taps(typed, on: "ar-letters"))
    let other = try #require(try fixtureEngine(.ar).candidates(input).first { $0.text == variant })
    let offset = config.alpha * (config.tapOffsetX * config.tapOffsetX + config.tapOffsetY * config.tapOffsetY) / (2 * config.sigma * config.sigma)
    #expect(abs(other.spatial - Double(typed.count) * offset) < 1e-9 && other.edits == 0 && other.completion == 0)
}

@Test func sentenceStartShareWeighsTheBaseBigramAfterSentenceStartOnly() throws {
    let lexicon = try #require(BaseLexicon(data: fixtureData(.en)))
    func lm(_ share: Double, _ context: [String]) -> Double {
        var config = EngineConfig()
        config.sentenceStartBigramShare = share
        let engine = Engine(lang: .en, lexicon: lexicon, layout: nil, config: config)
        return engine.lmLogProb("hello", word: lexicon.wordID(ident: "hello"), engine.lmContext(context))
    }
    #expect(lm(0.1, []) < lm(0.7, []))  // <s> hello is a base bigram: less of it
    #expect(lm(0.1, ["see"]) == lm(0.7, ["see"]))
}

@Test func moesOwnSentenceStartBigramKeepsItsWeight() throws {
    let lexicon = try #require(BaseLexicon(data: fixtureData(.en)))
    func lm(_ share: Double) throws -> Double {
        var config = EngineConfig()
        config.sentenceStartBigramShare = share
        let model = PersonalModel(store: try personalStore(Array(repeating: "yalla", count: 50)), config: config, clock: epoch)
        let engine = Engine(lang: .en, lexicon: lexicon, layout: nil, personal: model, config: config)
        return engine.lmLogProb("yalla", word: nil, engine.lmContext([]))
    }
    #expect(try lm(0.1) > lm(0.7))  // its bigram part stays, and the unigram part grows
}
