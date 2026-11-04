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
    var pad = Trackpad(startX: 100, downX: 100, rightToLeft: false)
    #expect(pad.offset(toX: 108) == 0)
    #expect(pad.offset(toX: 120) == 2)
    #expect(pad.offset(toX: 117) == 0)  // anchor moved to 118
    #expect(pad.offset(toX: 100) == -2)

    var arabic = Trackpad(startX: 100, downX: 100, rightToLeft: true)
    #expect(arabic.offset(toX: 118) == -2)
}

@Test(arguments: [
    (100.0, 108.0, true),  // a hold that never moved the cursor: a slow tap
    (100, 109, false),  // the hold moved the cursor
    (113, 113, false),  // a drag started it
    (88, 95, true),  // a hold, the finger 12 pt from where it went down
] as [(Double, Double, Bool)])
func trackpadReleaseTypesSpaceOnlyAfterAStillHold(startX: Double, releaseX: Double, expected: Bool) {
    var pad = Trackpad(startX: startX, downX: 100, rightToLeft: false)
    _ = pad.offset(toX: releaseX)
    #expect(pad.releaseTypesSpace == expected)
}

@Test(arguments: [
    // EN with hints drawn: the digit first and preselected.
    ("q", "1", [], true, ["1"], 0),
    ("e", "3", ["ë", "é", "e"], true, ["3", "ë", "é", "e"], 0),
    // Hints off, or Arabic: the letter right after the digit, or in its alternates, preselected.
    ("q", "1", [], false, ["1", "q"], 1),
    ("ض", "١", [], false, ["١", "ض"], 1),
    ("e", "3", ["ë", "é", "e", "è"], false, ["3", "ë", "é", "e", "è"], 3),
    ("ه", "8", ["ة", "هـ", "ه"], false, ["8", "ة", "هـ", "ه"], 3),
    // No hint: the output when the alternates hold it, else the first.
    ("a", nil, ["à", "a", "á"], true, ["à", "a", "á"], 1),
    ("َ", nil, ["ً", "ُ"], false, ["ً", "ُ"], 0),
] as [(String, String?, [String], Bool, [String], Int)])
func longPressStripPreselectsWhatTheKeyShows(output: String, hint: String?, alternates: [String], hintShown: Bool,
                                             items: [String], selected: Int) {
    let strip = longPressStrip(output: output, hint: hint, alternates: alternates, hintShown: hintShown)
    #expect(strip?.items == items && strip?.selected == selected)
}

@Test func keyWithoutHintOrAlternatesHasNoStrip() {
    #expect(longPressStrip(output: "x", hint: nil, alternates: [], hintShown: true) == nil)
}

@Test(arguments: [
    (false, nil, true),  // nothing to tap in the bar: the band is the top row's
    (false, 3.0, true),
    (true, nil, false),  // no key touched yet
    (true, 0.15, true),  // mid-typing
    (true, 0.39, true),
    (true, 0.4, false),  // after a pause: the bar's
    (true, 2.0, false),
] as [(Bool, Double?, Bool)])
func barBandGoesToTheTopRowOnlyMidTyping(tappable: Bool, since: Double?, keys: Bool) {
    #expect(BarBand.belongsToKeys(barTappable: tappable, sinceKeyDown: since) == keys)
}

@Test(arguments: [
    (true, false, 0.03, true),
    (true, false, 0.2, true),
    (true, false, 0.029, false),  // too short to be a real press
    (true, true, 0.5, false),  // the strip was open
    (false, false, 0.2, false),  // not a char key
] as [(Bool, Bool, Double, Bool)])
func cancelledPressCommitsARealLetterPress(isChar: Bool, stripOpen: Bool, held: Double, expected: Bool) {
    #expect(CancelledTouch.commits(isChar: isChar, stripOpen: stripOpen, heldFor: held) == expected)
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
