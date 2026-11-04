import Foundation
import Testing
@testable import KalamEngine

@Test func personalWordIsFoundThroughATypo() throws {
    let engine = try personalEngine(.en, ["kda kda"])
    #expect(suggestions(engine, "kfa").first == "kda")  // d and f are neighbours
}

@Test func pendingWordsAreNotSuggested() throws {
    let engine = try personalEngine(.en, ["kda"])
    #expect(!suggestions(engine, "kfa", limit: 10).contains("kda"))
}

@Test func moesCasingWinsOverTheCorpusCasing() throws {
    let engine = try personalEngine(.en, ["OK cool, OK"])
    #expect(suggestions(engine, "ok").first == "OK")
}

@Test func personalBigramOutranksTheBaseBigram() throws {
    let base = try fixtureEngine(.en)
    #expect(base.predict(context: ["see"]).first?.text == "you")
    let engine = try personalEngine(.en, Array(repeating: "see ya", count: 5))
    #expect(engine.predict(context: ["see"]).first?.text == "ya")
}

@Test func personalTrigramNeedsBothContextWords() throws {
    let engine = try personalEngine(.en, Array(repeating: "I'm going home", count: 3))
    let after = try #require(engine.predict(context: ["I'm", "going"], limit: 10).first { $0.ident == "home" })
    let without = try #require(engine.predict(context: ["you", "going"], limit: 10).first { $0.ident == "home" })
    #expect(after.lm > without.lm)
}

@Test func predictionsSkipThePreviousWordAndSentenceStart() throws {
    let engine = try personalEngine(.en, Array(repeating: "ha ha ha", count: 3))
    let idents = engine.predict(context: ["ha"], limit: 50).map(\.ident)
    #expect(!idents.contains("ha") && !idents.contains(sentenceStart) && !idents.isEmpty)
}

@Test func predictionsSkipAPendingWord() throws {
    let engine = try personalEngine(.en, ["see yuo"] + Array(repeating: "see ya", count: 2))  // yuo: one use, pending
    let idents = engine.predict(context: ["see"], limit: 50).map(\.ident)
    #expect(idents.contains("ya") && idents.contains("you") && !idents.contains("yuo"))
}

@Test func predictionsBackOffToUnigrams() throws {
    let idents = try fixtureEngine(.en).predict(context: ["zzz"]).map(\.ident)
    #expect(idents == ["the", "and", "to"])  // and / to tie, broken alphabetically
}

@Test func manualCorrectionPairIsBoosted() throws {
    let engine = try personalEngine(.en, []) {
        $0.addCorrection(lang: "en", typed: "thw", chosen: "the", rejected: false, at: 0)
    }
    let the = try #require(engine.candidates(InputState(context: [], taps: taps("thw"))).first { $0.ident == "the" })
    #expect(the.boosts == EngineConfig().correctionBoost)
}

@Test func blockedWordIsNeverSuggestedOrPredicted() throws {
    let engine = try personalEngine(.en, [])
    engine.personal?.block(.en, "hello", display: "hello")
    #expect(!suggestions(engine, "hel", limit: 20).contains("hello"))
    #expect(!engine.predict(context: [], limit: 50).map(\.ident).contains("hello"))
}

@Test func knownSpecialTokenIsSuggestedByPrefix() throws {
    let engine = try personalEngine(.en, ["mail me@x.com", "me@x.com"])
    #expect(engine.suggest(InputState(context: [], taps: "me@".map { Tap(String($0)) })).first?.text == "me@x.com")
    #expect(!suggestions(engine, "me", limit: 20).contains("me@x.com"))
}

@Test func arabicPersonalVariantsShareOneKey() throws {
    let engine = try personalEngine(.ar, ["إزيك إزيك يا عم", "إزيك"])
    let top = suggestions(engine, "ازيك")
    #expect(top.first == "إزيك" && top.contains("ازيك"))
}

@Test func personalTrieEvictsTheLowestDecayedCount() {
    let halfLife = EngineConfig().halfLife
    var trie = PersonalTrie(cap: 2, halfLife: halfLife)
    trie.set("old", norm: "old", display: "old", hits: Hits(count: 5, time: 0))
    trie.set("new", norm: "new", display: "new", hits: Hits(count: 1, time: 10 * halfLife))
    trie.set("mid", norm: "mid", display: "mid", hits: Hits(count: 2, time: 5 * halfLife))  // 2 > 5 / 32
    #expect(Set(trie.words.keys) == ["new", "mid"])
}

@Test func brokenStoreDegradesToBaseOnly() throws {
    let url = temporaryStoreURL()
    let store = try PersonalStore(url: url)
    try SQLite(url: url).execute("DROP TABLE words")
    let lexicon = try #require(BaseLexicon(data: fixtureData(.en)))
    let engine = Engine(lang: .en, lexicon: lexicon, layout: Layout.bundled("en-letters"), personal: PersonalModel(store: store))
    #expect(suggestions(engine, "teh").first == "the")
    #expect(engine.predict(context: ["see"]).first?.text == "you")
}

/// A tap halfway between l and p, after "hel": of hell and help, help wins on the LM alone. Taps
/// land where they fall, so the fixed offset is 0 here.
@Test func aLearnedKeyOffsetDecidesAnAmbiguousTap() throws {
    var config = EngineConfig()
    config.tapOffsetY = 0
    let centers = try #require(Layout.bundled("en-letters")).keyCenters()
    let (l, p) = (centers["l"]!, centers["p"]!)
    let input = InputState(context: [], taps: taps("hel") + [Tap("l", at: Point(x: (l.x + p.x) / 2, y: (l.y + p.y) / 2))])
    func first(_ samples: [Point]) throws -> String? {
        let store = try personalStore([]) { batch in
            if !samples.isEmpty { batch.keyOffsets[LearningBatch.KeyOffsetKey(lang: "en", key: "l")] = samples }
        }
        let lexicon = try #require(BaseLexicon(url: fixtures.appendingPathComponent("fixture-en.klex")))
        let engine = Engine(lang: .en, lexicon: lexicon, layout: Layout.bundled("en-letters"),
                            personal: PersonalModel(store: store, config: config, clock: epoch), config: config)
        return engine.candidates(input).first { ["hell", "help"].contains($0.ident) }?.ident
    }
    #expect(try first([]) == "help")
    // Moe's l taps land 0.3 key units high: the l key's center moves up toward the tap.
    #expect(try first(Array(repeating: Point(x: 0, y: -0.3), count: 300)) == "hell")
}

@Test func aSubstitutionMoeCorrectedTwiceIsCheaper() throws {
    let lettar = InputState(context: [], taps: "lettar".map { Tap(String($0)) })
    let once = try personalEngine(.en, []) { $0.addCorrection(lang: "en", typed: "tha", chosen: "the", rejected: false, at: 0) }
    #expect(once.suggest(lettar, limit: 5).first { $0.text == "letter" }?.edits == EngineConfig().farSubstitutionCost)
    let twice = try personalEngine(.en, []) {
        $0.addCorrection(lang: "en", typed: "tha", chosen: "the", rejected: false, at: 0)
        $0.addCorrection(lang: "en", typed: "sha", chosen: "she", rejected: false, at: 0)
    }
    #expect(twice.suggest(lettar, limit: 5).first { $0.text == "letter" }?.edits == EngineConfig().learnedConfusionCost)
}
