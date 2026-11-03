import Testing
@testable import KalamEngine

@Test func englishLettersCentersInKeyUnits() throws {
    let layout = try #require(Layout.bundled("en-letters"))
    let centers = layout.keyCenters()
    #expect(centers.count == 26)
    #expect(centers["q"] == Point(x: 0.5, y: 0.5))
    #expect(centers["p"] == Point(x: 9.5, y: 0.5))
    #expect(centers["a"] == Point(x: 1.0, y: 1.5))  // 9-key row is centered
    #expect(centers["z"] == Point(x: 2.0, y: 2.5))  // after a 1.5-wide shift
}

@Test func keyDefaultsApply() throws {
    let keys = try #require(Layout.bundled("en-letters")).rows.joined()
    let q = try #require(keys.first { $0.id == "q" })
    #expect((q.output, q.width, q.kind, q.popup) == ("q", 1, .char, true))
    let space = try #require(keys.first { $0.kind == .space })
    #expect((space.output, space.popup) == (" ", false))
}
