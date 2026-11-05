import Testing
@testable import KalamEngine

/// "see hell" with its last tap between l and p: a real word on commit; "help" once the next word is
/// "me", which Moe writes after help; kept before a word that doesn't say so.
@Test(arguments: [("me", "help"), ("there", nil)] as [(String, String?)])
func enginePostCorrectsWithTheNextWord(_ next: String, _ expected: String?) throws {
    let engine = try personalEngine(.en, ["help me", "help me", "help me"])
    let centers = try #require(Layout.bundled("en-letters")?.keyCenters())
    let l = try #require(centers["l"]), p = try #require(centers["p"])
    let input = InputState(context: ["see"], taps: taps("hel") + [Tap("l", at: Point(x: (l.x + p.x) / 2, y: (l.y + p.y) / 2))])
    #expect(engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings()) == nil)
    #expect(engine.postCorrection(input, next: next, traits: FieldTraits(), settings: Settings())?.ident == expected)
}
