import Testing
@testable import kalam_cli

private func result(_ literal: String, _ kinds: Set<TypoKind>, realWord: Bool = false, word: String? = nil, top: String? = nil) -> NoisyResult {
    NoisyResult(literal: literal, kinds: kinds, realWord: realWord, word: word ?? literal, top: top)
}

@Test func ratesCountFixesTopRanksAndWrongChanges() {
    var tally = NoiseTally()
    tally.add("brown", noisy: result("brow", [.omission], realWord: true, top: "brown"), clean: "brown")
    tally.add("fox", noisy: result("fo", [.omission], word: "fox", top: "fox"), clean: "fox")
    tally.add("the", noisy: nil, clean: "then")
    #expect((tally.words, tally.noisy, tally.fixed, tally.rankedFirst, tally.wrongChanges) == (3, 2, 1, 2, 1))
    #expect((tally.realWord, tally.realWordFixed) == (1, 0))
    #expect(tally.misses == ["real-word": 1])
}

@Test func aMissIsBucketedByItsKinds() {
    #expect(NoiseTally.bucket([.swap, .extraTap], realWord: false) == "extra tap+swap")
    #expect(NoiseTally.bucket([.substitution], realWord: true) == "real-word")
}

@Test func samplesShowTheKindsUpToTheLimit() {
    var tally = NoiseTally(sampleLimit: 2)
    tally.add("brown", noisy: result("brow", [.omission], realWord: true), clean: "brown")
    tally.add("the", noisy: nil, clean: "then")
    tally.add("fox", noisy: result("fo", [.omission]), clean: "fox")
    #expect(tally.samples == ["miss   [real-word: omission] brown: typed brow -> brow (top none)", "wrong  the -> then"])
}

@Test func foldsSumAndKeepTheFirstSamples() {
    var a = NoiseTally(sampleLimit: 1), b = NoiseTally(sampleLimit: 1)
    a.add("the", noisy: nil, clean: "then")
    b.add("fox", noisy: result("fo", [.omission]), clean: "fox")
    let sum = a + b
    #expect((sum.words, sum.noisy, sum.wrongChanges) == (2, 1, 1))
    #expect(sum.misses == ["omission": 1])
    #expect(sum.samples == ["wrong  the -> then"])
}
