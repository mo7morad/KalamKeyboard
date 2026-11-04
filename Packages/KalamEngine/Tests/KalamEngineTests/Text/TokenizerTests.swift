import Testing
@testable import KalamEngine

@Test(arguments: [
    ("I'm going, don't wait!", ["I'm", "going", "don't", "wait"]),
    ("أنا مُحَمَّد، وعايز", ["أنا", "محمد", "وعايز"]),
    ("ok 3ashan kda", ["ok", "3ashan", "kda"]),
    ("ســلام يا", ["سلام", "يا"]),  // tatweel stripped like tashkeel
    ("mail me@x.com now", ["mail", "me@x.com", "now"]),
    ("in 2026 at www.x.com, ask @moe #kalam", ["in", "at", "www.x.com", "ask", "@moe", "#kalam"]),
])
func splitsWords(_ input: String, _ expected: [String]) {
    #expect(tokenize(input).filter { $0.kind != .sentenceEnd }.map(\.surface) == expected)
}

@Test func tagsKinds() {
    #expect(tokenize("hi يا me@x.com").map(\.kind) == [.en, .ar, .tok])
}

@Test func sentenceEndsOnPunctuationAndNewline() {
    let kinds = tokenize("hi. ok!? يا؟\nbye").map(\.kind)
    #expect(kinds == [.en, .sentenceEnd, .en, .sentenceEnd, .ar, .sentenceEnd, .en])
}

@Test(arguments: [
    ("", ["<s>"]),
    ("Hello", ["<s>", "hello"]),
    ("well. See you", ["see", "you"]),
    ("see you.", ["<s>"]),
])
func contextIsLastTwoIdentsOfTheSentence(_ text: String, _ expected: [String]) {
    #expect(contextIdents(text) == expected)
}

@Test(arguments: [("Don’t", Token.Kind.en, "don't"), ("I'M", .en, "i'm"), ("أنـــا", .ar, "أنا"), ("#Kalam", .tok, "#Kalam")])
func identFollowsSpec63(_ surface: String, _ kind: Token.Kind, _ expected: String) {
    #expect(ident(surface, kind: kind) == expected)
}
