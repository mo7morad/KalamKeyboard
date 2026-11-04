import Testing
@testable import KalamEngine

private func tapShift(_ shift: inout ShiftState, at time: Double) {
    shift.shiftDown(at: time)
    shift.shiftUp()
}

@Test func shiftTapsOnceThenLocksOnDoubleTap() {
    var shift = ShiftState()
    tapShift(&shift, at: 0)
    #expect(shift.mode == .once)
    shift.letterTyped()
    #expect(shift.mode == .off)

    tapShift(&shift, at: 1)
    tapShift(&shift, at: 1.2)
    #expect(shift.mode == .locked)
    shift.letterTyped()
    shift.setAuto(false)
    #expect(shift.mode == .locked)
    tapShift(&shift, at: 1.3)
    #expect(shift.mode == .off)
}

@Test func slowSecondShiftTapTurnsShiftOff() {
    var shift = ShiftState()
    tapShift(&shift, at: 0)
    tapShift(&shift, at: 0.5)
    #expect(shift.mode == .off)
}

@Test func doubleTapFromAutoShiftLocks() {
    var shift = ShiftState()
    shift.setAuto(true)
    tapShift(&shift, at: 0)
    #expect(shift.mode == .off)
    tapShift(&shift, at: 0.2)
    #expect(shift.mode == .locked)
}

@Test func heldShiftCapitalizesEveryLetterUntilLifted() {
    var shift = ShiftState()
    shift.shiftDown(at: 0)
    for _ in 0..<3 {
        #expect(shift.capitalizes)
        shift.letterTyped()
        shift.setAuto(false)  // the edit's auto-shift refresh leaves a held shift on
        #expect(shift.mode == .once)
    }
    shift.shiftUp()
    #expect(shift.mode == .off)
    tapShift(&shift, at: 0.1)  // not a double tap: the hold ended the tap sequence
    #expect(shift.mode == .once)
}

@Test func heldShiftFromAutoShiftStillCapitalizes() {
    var shift = ShiftState()
    shift.setAuto(true)
    shift.shiftDown(at: 0)  // turns the auto-shift off, but the finger is still down
    #expect(shift.mode == .off)
    #expect(shift.capitalizes)
    shift.letterTyped()
    #expect(shift.mode == .once)
    shift.shiftUp()
    #expect(shift.mode == .off)
}

@Test func heldShiftNeverEndsCapsLock() {
    var shift = ShiftState()
    tapShift(&shift, at: 0)
    shift.shiftDown(at: 0.2)
    #expect(shift.mode == .locked)
    shift.letterTyped()
    shift.letterTyped()
    shift.shiftUp()
    #expect(shift.mode == .locked)
}

@Test func shiftTapWithoutLettersStaysOneShot() {
    var shift = ShiftState()
    shift.shiftDown(at: 0)
    shift.shiftUp()
    #expect(shift.mode == .once)
    #expect(shift.capitalizes)
    shift.letterTyped()
    #expect(shift.mode == .off)
    #expect(!shift.capitalizes)
}

@Test(arguments: [
    (nil, Autocapitalization.sentences, true),
    ("", .sentences, true),
    ("Hi. ", .sentences, true),
    ("Hi?  ", .sentences, true),
    ("Hi.", .sentences, false),
    ("Hi ", .sentences, false),
    ("He said \"hi.\" ", .sentences, true),
    ("(Done.) ", .sentences, true),
    ("Really?\" ", .sentences, true),
    ("Wow!\u{201D} ", .sentences, true),
    ("Fine.\u{2019}) ", .sentences, true),
    ("\u{AB}Oui.\u{BB} ", .sentences, true),
    ("He said \"hi\" ", .sentences, false),
    ("(see this) ", .sentences, false),
    ("Hi.\"", .sentences, false),
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

@Test(arguments: [
    (true, true, true, "hi ", SpaceEdit.period),  // a suggestion + space + space
    (true, false, true, "hi ", .nothing),  // the space right after a suggestion's auto-space
    (true, false, false, "hi ", .nothing),
    (true, true, true, "hi. ", .space),  // after punctuation's ". " and a swallowed space: no second period
    (false, true, true, "hi ", .period),
    (false, true, false, "hi ", .space),  // double-space period off
    (false, true, true, "hi  ", .space),
    (false, false, true, "hi", .space),
] as [(Bool, Bool, Bool, String, SpaceEdit)])
func spaceKeyEdit(autoSpace: Bool, lastKeyWasSpace: Bool, setting: Bool, before: String, expected: SpaceEdit) {
    #expect(spaceEdit(before: before, afterAutoSpace: autoSpace, lastKeyWasSpace: lastKeyWasSpace, doubleSpacePeriod: setting) == expected)
}

@Test func backspaceSwitchesToWordsAfterFifteenRepeats() {
    #expect(!BackspaceRepeat.deletesWord(repeat: 14))
    #expect(BackspaceRepeat.deletesWord(repeat: 15))
}

@Test(arguments: [(0, 0.1), (4, 0.1), (5, 0.06), (13, 0.06), (14, 0.15), (15, 0.15), (40, 0.15)] as [(Int, Double)])
func backspaceRepeatAccelerates(repeatNumber: Int, interval: Double) {
    #expect(BackspaceRepeat.interval(afterRepeat: repeatNumber) == interval)
}

@Test func backspaceHoldTiming() {
    // The first word goes about 1.7 s after touch-down, after 16 characters.
    let firstWord = BackspaceRepeat.delay + (0..<15).map { BackspaceRepeat.interval(afterRepeat: $0) }.reduce(0, +)
    #expect(abs(firstWord - 1.69) < 1e-9)
}

@Test(arguments: [("hello world", 5), ("hello world  ", 7), ("hello", 5), ("", 1), ("انا رايح ", 5)])
func wordDeleteLength(before: String, expected: Int) {
    #expect(BackspaceRepeat.wordLength(before: before) == expected)
}

@Test func trackpadMovesOneCharPerNinePointsWhenSlow() {
    var pad = Trackpad(startX: 100, rightToLeft: false)
    #expect(pad.offset(toX: 108, at: 0) == 0)
    #expect(pad.offset(toX: 120, at: 0.2) == 2)  // 60 pt/s
    #expect(pad.offset(toX: 117, at: 0.3) == 0)  // anchor moved to 118
    #expect(pad.offset(toX: 100, at: 0.5) == -2)  // 85 pt/s

    var arabic = Trackpad(startX: 100, rightToLeft: true)
    #expect(arabic.offset(toX: 118, at: 0) == -2)
}

@Test func trackpadSpeedsUpWithAFastFinger() {
    var fast = Trackpad(startX: 100, rightToLeft: false)
    _ = fast.offset(toX: 100, at: 0)
    #expect(fast.offset(toX: 136, at: 0.04) == 10)  // 900 pt/s: 3.6 pt per character
    var medium = Trackpad(startX: 100, rightToLeft: false)
    _ = medium.offset(toX: 100, at: 0)
    #expect(medium.offset(toX: 135, at: 0.1) == 5)  // 350 pt/s: 6.3 pt per character
}

@Test(arguments: [(0.0, 9.0), (100, 9), (350, 6.3), (600, 3.6), (2000, 3.6)] as [(Double, Double)])
func trackpadPointsPerCharRamp(speed: Double, expected: Double) {
    #expect(abs(Trackpad.pointsPerChar(speed: speed) - expected) < 1e-9)
}

// The view starts the trackpad where the finger is, after a 0.4 s hold or a slide past 12 pt, so a
// sloppy tap that slid 13 pt starts it and is still a tap until the cursor moves.
@Test(arguments: [
    (100.0, false),  // no further move: a tap, so it types a space
    (108, false),
    (109, true),
    (92, false),
    (91, true),
] as [(Double, Bool)])
func trackpadIsATapUntilTheCursorMoves(lastX: Double, moved: Bool) {
    var pad = Trackpad(startX: 100, rightToLeft: false)
    _ = pad.offset(toX: lastX, at: 1)
    #expect(pad.movedCursor == moved)
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
    (false, nil, true),  // nothing to pick above the touch (empty slot, a button): the band is the top row's
    (false, 3.0, true),
    (true, nil, false),  // no key touched yet
    (true, 0.15, true),  // mid-typing
    (true, 0.39, true),
    (true, 0.4, false),  // after a pause: the bar's
    (true, 2.0, false),
] as [(Bool, Double?, Bool)])
func barBandGoesToTheBarOnlyOverAPickAfterAPause(target: Bool, since: Double?, keys: Bool) {
    #expect(BarBand.belongsToKeys(barTarget: target, sinceKeyDown: since) == keys)
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

@Test(arguments: [
    (23.9, 0.0, 0.008, false),  // under 0.6 of a key: the finger itself (a slide, a thumb rolling off as it lifts)
    (24, 0, 0.008, true),  // 0.6 of a key from rest: the next finger landing
    (90, 2, 0.008, true),  // a jump across the keyboard
    (90, 9.9, 0.008, true),
    (90, 10, 0.008, false),  // a quarter key in the sample just before: a flick or a quick drag
    (90, 10, 0.019, false),
    (90, 10, 0.02, true),  // no sample for 20 ms: that finger was at rest (it landed with a jump, then held still)
] as [(Double, Double, Double, Bool)])
func suddenMoveFromRestIsANewTouch(step: Double, before: Double, interval: Double, newTouch: Bool) {
    #expect(SuddenMove.isNewTouch(step: step, stepBefore: before, interval: interval, keyWidth: 40) == newTouch)
}
