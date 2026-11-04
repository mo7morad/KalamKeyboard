import Foundation
import Testing
@testable import KalamEngine

private let en = Layout.bundled("en-letters")!

/// Taps at the en-letters key centers, moved by (dx, dy).
private func shifted(_ typed: String, _ dx: Double, _ dy: Double) -> [Tap] {
    taps(typed).map { Tap($0.char, at: $0.point.map { Point(x: $0.x + dx, y: $0.y + dy) }) }
}

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Test func tapsAlignToTheLettersOneToOne() {
    let samples = offsetSamples("Hello", taps: shifted("hello", 0.1, -0.2), layout: en)
    #expect(samples.map(\.key) == ["h", "e", "l", "l", "o"])
    #expect(samples.allSatisfy { close($0.offset.x, 0.1) && close($0.offset.y, -0.2) })
}

@Test func aTapFarFromItsLetterIsSkipped() {
    // "teh" autocorrected to "the": e and h are more than a key apart, so only t pairs.
    let samples = offsetSamples("the", taps: taps("teh"), layout: en)
    #expect(samples.map(\.key) == ["t"])
}

@Test func pointlessTapsAreSkippedAndCountsMustMatch() {
    // The apostrophe has no key and normalizes away, so the 4 pointed taps pair with d, o, n, t.
    #expect(offsetSamples("don't", taps: taps("don't"), layout: en).map(\.key) == ["d", "o", "n", "t"])
    #expect(offsetSamples("hello", taps: taps("helo"), layout: en).isEmpty)  // an omission: no alignment
    #expect(offsetSamples("hello", taps: "hello".map { Tap(String($0)) }, layout: en).isEmpty)
}

@Test func anArabicLetterOnTwoKeysPairsWithTheNearest() throws {
    let ar = try #require(Layout.bundled("ar-letters"))
    let centers = ar.keyCenters()
    let samples = offsetSamples("هى", taps: [Tap("ه", at: centers["ه"]), Tap("ى", at: centers["ى"])], layout: ar)
    #expect(samples.map(\.key) == ["ه", "ى"])  // ى normalizes to ي, but its own key is the nearest
}

@Test func runningMeanStopsGrowingAtTheCap() {
    var offset = KeyOffset()
    for _ in 0..<3 { offset.add(Point(x: 0, y: 0), maxSamples: 3) }
    offset.add(Point(x: 3, y: -3), maxSamples: 3)
    #expect(offset.n == 3 && close(offset.dx, 1) && close(offset.dy, -1))  // weight 1/3, not 1/4
}

@Test func thinKeysShrinkTowardTheAllKeysMeanAndThatTowardTheFixedOffset() {
    var config = EngineConfig()
    (config.tapOffsetX, config.tapOffsetY, config.keyOffsetPrior) = (0, -0.13, 20)
    let offsets = KeyOffsets(["a": KeyOffset(n: 20, dx: 0, dy: -0.25)], config: config)
    #expect(close(offsets.global.y, (20 * -0.25 + 20 * -0.13) / 40))
    #expect(close(offsets.offset("a").y, (20 * -0.25 + 20 * offsets.global.y) / 40))
    #expect(close(offsets.offset("s").y, offsets.global.y))  // no data: the all-keys mean
    #expect(close(KeyOffsets([:], config: config).offset("a").y, -0.13))  // no data at all: the fixed offset
}

@Test func theEffectiveOffsetIsCappedSoTheKeyCenterStaysOnTheKey() {
    var config = EngineConfig()
    config.tapOffsetY = 0
    let offsets = KeyOffsets(["a": KeyOffset(n: 10_000, dx: 0.6, dy: -0.8)], config: config)
    let p = offsets.offset("a")
    #expect(close((p.x * p.x + p.y * p.y).squareRoot(), config.keyOffsetCap))
    #expect(close(p.x / p.y, 0.6 / -0.8))  // same direction
}

@Test func traceTouchesAreMeasuredToTheKeyTheyEndedOn() {
    let trace = """
        1000.0 touch began q at 0.48,0.30 lag 1.2 ms
        1080.5 touch ended q at 0.50,0.40 lag 1.0 ms
        1200.0 touch ended q at 0.60,0.20 lag 0.8 ms
        1300.0 touch ended space at 5.00,3.40 lag 0.8 ms
        1400.0 touch ended 1 at 0.50,0.40 lag 0.8 ms
        1500.0 touch ended a at -1.00,-1.00 lag 0.8 ms
        1600.0 commitWord "qq" delete 0
        """
    let stats = traceOffsets(trace, layout: en)
    #expect(stats.keys.sorted() == ["q"])
    let q = stats["q"]!
    #expect(q.n == 2 && close(q.dx, 0.05) && close(q.dy, -0.2))
}

@Test func oneLetterSubstitutionsSeenTwiceBecomeConfusionPairs() {
    func key(_ typed: String, _ chosen: String, rejected: Bool = false, lang: String = "en") -> LearningBatch.CorrectionKey {
        LearningBatch.CorrectionKey(lang: lang, typed: typed, chosen: chosen, rejected: rejected)
    }
    let corrections: Set = [
        key("tha", "the"), key("sha", "she"),  // a -> e twice
        key("wiat", "wait"),  // two positions differ: a swap, not a substitution
        key("helo", "hello"),  // lengths differ
        key("lat", "let"), key("mat", "met", rejected: true),  // a rejection doesn't count
        key("xo", "so"),  // x -> s once
    ]
    let pairs = confusionPairs(corrections, minCorrections: 2)
    #expect(pairs["en"] == [confusionPair(Array("a".utf16)[0], Array("e".utf16)[0])])
}
