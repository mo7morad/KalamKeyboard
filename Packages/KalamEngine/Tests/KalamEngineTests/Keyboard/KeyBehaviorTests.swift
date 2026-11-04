import Testing
@testable import KalamEngine

@Test func shiftTapsOnceThenLocksOnDoubleTap() {
    var shift = ShiftState()
    shift.tap(at: 0)
    #expect(shift.mode == .once)
    shift.letterTyped()
    #expect(shift.mode == .off)

    shift.tap(at: 1)
    shift.tap(at: 1.2)
    #expect(shift.mode == .locked)
    shift.letterTyped()
    shift.setAuto(false)
    #expect(shift.mode == .locked)
    shift.tap(at: 1.3)
    #expect(shift.mode == .off)
}

@Test func slowSecondShiftTapTurnsShiftOff() {
    var shift = ShiftState()
    shift.tap(at: 0)
    shift.tap(at: 0.5)
    #expect(shift.mode == .off)
}

@Test func doubleTapFromAutoShiftLocks() {
    var shift = ShiftState()
    shift.setAuto(true)
    shift.tap(at: 0)
    #expect(shift.mode == .off)
    shift.tap(at: 0.2)
    #expect(shift.mode == .locked)
}

@Test(arguments: [
    (nil, Autocapitalization.sentences, true),
    ("", .sentences, true),
    ("Hi. ", .sentences, true),
    ("Hi?  ", .sentences, true),
    ("Hi.", .sentences, false),
    ("Hi ", .sentences, false),
    ("Hi\n", .sentences, true),
    ("Hi there ", .words, true),
    ("Hi", .words, false),
    ("hi", .allCharacters, true),
    ("", .none, false),
] as [(String?, Autocapitalization, Bool)])
func autoShiftRule(before: String?, mode: Autocapitalization, expected: Bool) {
    #expect(shouldAutoShift(before: before, autocapitalization: mode) == expected)
}

@Test(arguments: [("hi ", true), ("7 ", true), ("hi. ", false), ("hi  ", false), (" ", false), ("hi", false)])
func doubleSpacePeriod(before: String, expected: Bool) {
    #expect(doubleSpaceBecomesPeriod(before: before) == expected)
}

@Test func backspaceSwitchesToWordsAfterFifteenRepeats() {
    #expect(!BackspaceRepeat.deletesWord(repeat: 14))
    #expect(BackspaceRepeat.deletesWord(repeat: 15))
}

@Test(arguments: [("hello world", 5), ("hello world  ", 7), ("hello", 5), ("", 1), ("انا رايح ", 5)])
func wordDeleteLength(before: String, expected: Int) {
    #expect(BackspaceRepeat.wordLength(before: before) == expected)
}

@Test func trackpadMovesOneCharPerNinePoints() {
    var pad = Trackpad(startX: 100, rightToLeft: false)
    #expect(pad.offset(toX: 108) == 0)
    #expect(pad.offset(toX: 120) == 2)
    #expect(pad.offset(toX: 117) == 0)  // anchor moved to 118
    #expect(pad.offset(toX: 100) == -2)

    var arabic = Trackpad(startX: 100, rightToLeft: true)
    #expect(arabic.offset(toX: 118) == -2)
}

@Test(arguments: [(0.0, 0), (12, 0), (12.5, 1), (33.9, 1), (34, 2), (100, 5), (-40, 0)])
func backspaceSwipeDeletesOneMoreWordEvery22Points(dx: Double, expected: Int) {
    #expect(BackspaceSwipe.words(left: dx) == expected)
}

@Test(arguments: [
    (0, 0.0, 70.0, 0.2, true),
    (1, 29, 120, 0.3, true),
    (2, 0, 80, 0.1, false),  // starts on the bottom letter row
    (0, 0, 69, 0.1, false),  // too short
    (0, 30, 90, 0.1, false),  // too sideways
    (0, 0, 90, 0.31, false),  // too slow
] as [(Int, Double, Double, Double, Bool)])
func swipeDownHidesOnlyWhenFastStraightAndFromTheUpperRows(row: Int, dx: Double, dy: Double, elapsed: Double, expected: Bool) {
    #expect(SwipeDownHide.triggers(startRow: row, dx: dx, dy: dy, elapsed: elapsed) == expected)
}
