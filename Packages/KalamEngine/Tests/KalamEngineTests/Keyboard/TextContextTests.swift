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

@Test(arguments: [
    ("hello", nil, false),  // EN text on the AR layout
    ("مرحبا", nil, true),  // AR text on the EN layout
    ("hello مرحبا", nil, true),  // cursor after the Arabic part
    ("hello", " مرحبا", false),  // cursor after the English part
    ("مرحبا 123, 😀 ", nil, true),  // digits, punctuation, emoji and spaces skipped
    ("", "مرحبا", true),  // nothing before: the text after
    ("بِ", nil, true),  // a mark is skipped, its letter counts
    ("123 ", "!", nil),  // digits only: the layout decides
    ("", nil, nil),
    (nil, nil, nil),
] as [(String?, String?, Bool?)])
func trackpadDirectionFollowsTheTextAtTheCursor(before: String?, after: String?, expected: Bool?) {
    #expect(textIsRightToLeft(before: before, after: after) == expected)
}

/// One autocorrect slot, "teh" → "the", after its commit inserted `tail` (deleting `deleting`
/// characters of an auto-space first), backspaced once per step against the text that results.
@Test(arguments: [
    // Space: the auto-space and the word go back in one backspace.
    ([" "], 0, "the ", [AutocorrectUndo.Step.revert(delete: 4, insert: "teh")]),
    // Punctuation and return: a plain backspace first, then the revert.
    ([","], 0, "the,", [.delete, .revert(delete: 3, insert: "teh")]),
    (["."], 0, "the.", [.delete, .revert(delete: 3, insert: "teh")]),
    (["?"], 0, "the?", [.delete, .revert(delete: 3, insert: "teh")]),
    (["!"], 0, "the!", [.delete, .revert(delete: 3, insert: "teh")]),
    (["\n"], 0, "the\n", [.delete, .revert(delete: 3, insert: "teh")]),
    // Punctuation after the auto-space brings its own space.
    ([" ", ", "], 1, "the, ", [.delete, .delete, .revert(delete: 3, insert: "teh")]),
    // The text moved on under the slot.
    ([","], 0, "they,", [.gone]),
    ([" "], 0, "the  ", [.gone]),
] as [([String], Int, String, [AutocorrectUndo.Step])])
func autocorrectUndoStepsBackThroughItsTail(tails: [String], deleting: Int, text: String, steps: [AutocorrectUndo.Step]) {
    var slot: AutocorrectUndo? = AutocorrectUndo(literal: "teh", taps: [], replacement: "the")
    for (i, tail) in tails.enumerated() { slot = slot?.typed(tail, deleting: i == tails.count - 1 ? deleting : 0) }
    var before = text
    for expected in steps {
        let step = slot?.backspace(before: before)
        #expect(step == expected)
        before.removeLast()
    }
}

@Test func autocorrectUndoSlotEndsWhenTheKeyDeletesPastItsTail() {
    let slot = AutocorrectUndo(literal: "teh", taps: [], replacement: "the")
    #expect(slot.typed(",", deleting: 1) == nil)
}

@Test(arguments: [
    ("lo world", "lo"),
    ("lo", "lo"),
    (" world", ""),
    ("", ""),
    ("'t go", "'t"),
    ("s' are", "s"),
    ("lo.", "lo"),
])
func currentWordTailAfterCursor(text: String, expected: String) {
    #expect(currentWordTail(after: text) == expected)
}

@Test(arguments: [
    ("go to www.goo", true),
    ("see a/b", true),
    ("e.g", true),
    ("mail x@y", true),
    ("time 10:3", true),
    ("C:\\Users\\mo", true),
    ("😂teh", true),
    ("❤️teh", true),
    ("hello teh", false),
    ("(teh", false),
    ("I don't", false),
    ("teh", false),
    ("www.x.com teh", false),
    ("انا رايح", false),
])
func nonWordTokenBeforeTheCursor(text: String, inside: Bool) {
    #expect(insideNonWordToken(before: text) == inside)
}

@Test func retypingALiteralWhereItWasCorrectedMatches() {
    var recent = RecentAutocorrects()
    recent.add(literal: "teh", replacement: "the", before: "I saw ")
    #expect(recent.retyped("teh", before: "I saw ")?.replacement == "the")
    #expect(recent.retyped("teh", before: "you saw ") == nil)  // another spot
    #expect(recent.retyped("tge", before: "I saw ") == nil)
}

@Test func retypeMatchComparesOnlyTheLast32Characters() {
    var recent = RecentAutocorrects()
    let long = String(repeating: "x", count: 40) + " I saw "
    recent.add(literal: "teh", replacement: "the", before: long)
    #expect(recent.retyped("teh", before: "older text " + long.suffix(32)) != nil)
}

@Test func revertMemoryKeepsTheLastTen() {
    var recent = RecentAutocorrects()
    for i in 0..<11 { recent.add(literal: "teh\(i)", replacement: "the", before: "") }
    #expect(recent.retyped("teh0", before: "") == nil)
    #expect(recent.retyped("teh1", before: "") != nil)
    let last = recent.retyped("teh10", before: "")!
    recent.remove(last)
    #expect(recent.retyped("teh10", before: "") == nil)
}

/// "teh" was corrected to "the" after "I saw "; the cursor then moves into or after it.
@Test(arguments: [
    ("I saw the", " cat", true),  // right after the word
    ("I saw th", "e cat", true),  // inside it
    ("I saw t", "he", true),
    ("I saw ", "the cat", false),  // before it
    ("I saw the ", "cat", false),
    ("I saw them", "", false),  // another word
    ("You saw the", "", false),  // another spot
])
func correctedWordAroundTheCursor(before: String, after: String, offered: Bool) {
    var recent = RecentAutocorrects()
    recent.add(literal: "teh", replacement: "the", before: "I saw ")
    #expect((recent.corrected(before: before, after: after)?.literal == "teh") == offered)
}
