import KalamEngine
import Testing
@testable import kalam_cli

private let layout = Layout.bundled("en-letters")!

private func typed(_ word: String, bias: Point = Point(x: 0, y: 0), omission: Double = 0, extra: Double = 0, swap: Double = 0)
    -> (literal: String, kinds: Set<TypoKind>) {
    let typist = NoisyTypist(layout: layout, sigma: 0, bias: bias, omissionRate: omission, extraRate: extra, swapRate: swap)
    var rng = SplitMix64(state: 1)
    let (taps, kinds) = typist.taps(word, using: &rng)
    return (taps.map(\.char).joined(), kinds)
}

@Test func noNoiseTypesTheWord() {
    #expect(typed("brown") == ("brown", []))
}

@Test func aTapOnAnotherKeyIsASubstitution() {
    #expect(typed("brown", bias: Point(x: 1, y: 0)) == ("ntpem", [.substitution]))
}

@Test func eachEditIsRecordedByKind() {
    #expect(typed("ab", swap: 1) == ("ba", [.swap]))
    #expect(typed("ab", omission: 1) == ("", [.omission]))
    #expect(typed("a", omission: 1) == ("a", []))  // a one-letter word keeps its letter
    #expect(typed("ab", extra: 1).literal.count == 4)
    #expect(typed("ab", extra: 1).kinds == [.extraTap])
}
