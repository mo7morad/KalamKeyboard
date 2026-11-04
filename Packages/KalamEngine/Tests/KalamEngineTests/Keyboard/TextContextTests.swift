import Testing
@testable import KalamEngine

@Test(arguments: [
    ("hello wor", "wor"),
    ("hello ", ""),
    ("", ""),
    ("I don't", "don't"),
    ("say 'hi", "hi"),
    ("(tomo", "tomo"),
    ("end.next", "next"),
    ("mail me@x.co", "me@x.co"),
    ("ok 3ashan", "3ashan"),
    ("انا رايح", "رايح"),
    ("مُحَمَّد", "مُحَمَّد"),
])
func currentWordBeforeCursor(text: String, expected: String) {
    #expect(currentWord(before: text) == expected)
}

@Test(arguments: [
    ("", ["<s>"]),
    ("see you tomo", ["see", "you"]),
    ("see you ", ["see", "you"]),
    ("Hi. ", ["<s>"]),
    ("Hi. how", ["<s>"]),
    ("Hi. how are", ["<s>", "how"]),
    ("done\nok", ["<s>"]),
    ("وانا رايح ", ["وانا", "رايح"]),
] as [(String, [String])])
func contextWordsSkipTheCurrentWord(text: String, expected: [String]) {
    #expect(contextWords(before: text) == expected)
}

@Test func resyncKeepsMatchingTapsAndAddsPointlessOnes() {
    let typed = [Tap("t", at: Point(x: 4.5, y: 0.5)), Tap("e", at: Point(x: 2.5, y: 0.5)), Tap("h", at: Point(x: 5.5, y: 1.5))]
    let shorter = resyncedTaps(typed, to: "te")
    #expect(shorter.map(\.char) == ["t", "e"])
    #expect(shorter.allSatisfy { $0.point != nil })

    let host = resyncedTaps(typed, to: "tea")
    #expect(host.map(\.char) == ["t", "e", "a"])
    #expect(host.map { $0.point == nil } == [false, false, true])

    #expect(resyncedTaps(typed, to: "").isEmpty)
    #expect(resyncedTaps([], to: "hi").map(\.char) == ["h", "i"])
}

@Test(arguments: [("the", true, "The"), ("the", false, "the"), ("iPhone", true, "iPhone"), ("London", true, "London"), ("انا", true, "انا")])
func displayCasing(word: String, capitalized: Bool, expected: String) {
    #expect(cased(word, capitalized: capitalized) == expected)
}

@Test(arguments: [
    (".", true, 1, ". "), ("،", true, 1, "، "), ("؟", true, 1, "؟ "),
    (":", true, 1, ":"), (")", true, 1, ")"), ("\"", true, 1, "\""),
    ("-", true, 0, "-"), (".", false, 0, "."),
])
func punctuationSpacing(char: String, autoSpace: Bool, delete: Int, insert: String) {
    let edit = punctuationEdit(char, afterAutoSpace: autoSpace)
    #expect(edit.delete == delete)
    #expect(edit.insert == insert)
}

@Test func wordCharacters() {
    #expect(continuesWord("a", word: ""))
    #expect(continuesWord("ع", word: ""))
    #expect(continuesWord("'", word: "don"))
    #expect(!continuesWord("'", word: ""))
    #expect(continuesWord(".", word: "me@x"))
    #expect(!continuesWord(".", word: "me"))
    #expect(!continuesWord(",", word: "me"))
    #expect(!continuesWord(" ", word: "me"))
}
