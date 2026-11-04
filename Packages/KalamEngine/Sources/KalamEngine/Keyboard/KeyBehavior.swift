import Foundation

/// Shift and caps lock (SPEC 5.2): a tap shifts one letter, a second tap within 0.3 s locks caps.
/// While the finger that went down on shift stays down, every letter is a capital; if letters were
/// typed during the hold, lifting it turns shift off (caps lock stays).
public struct ShiftState: Sendable {
    public enum Mode: Sendable { case off, once, locked }

    static let doubleTapWindow: TimeInterval = 0.3

    public private(set) var mode: Mode = .off
    private var lastTap: TimeInterval?
    private var held = false
    private var typedWhileHeld = false

    public init() {}

    /// Whether the next letter is a capital: shift is on, or held.
    public var capitalizes: Bool { mode != .off || held }

    public mutating func shiftDown(at time: TimeInterval) {
        held = true
        typedWhileHeld = false
        if mode == .locked {
            mode = .off
            lastTap = nil
        } else if let last = lastTap, time - last <= Self.doubleTapWindow {
            mode = .locked
            lastTap = nil
        } else {
            mode = mode == .off ? .once : .off
            lastTap = time
        }
    }

    /// The shift finger lifted: after letters typed during the hold, shift goes off.
    public mutating func shiftUp() {
        guard held else { return }
        held = false
        guard typedWhileHeld else { return }
        lastTap = nil
        if mode != .locked { mode = .off }
    }

    /// A letter was typed: a one-shot shift ends, unless shift is held (then it stays on).
    public mutating func letterTyped() {
        if held {
            typedWhileHeld = true
            if mode == .off { mode = .once }
        } else if mode == .once {
            mode = .off
        }
    }

    /// Auto-shift (SPEC 8.6) sets or clears a one-shot shift, and never touches caps lock or a held shift.
    public mutating func setAuto(_ on: Bool) {
        if mode != .locked, !held { mode = on ? .once : .off }
    }
}

/// Mirrors UITextAutocapitalizationType without importing UIKit.
public enum Autocapitalization: Sendable { case none, words, sentences, allCharacters }

/// SPEC 8.6 auto-shift: at the start of the field, after a sentence end plus space (closing quotes
/// and brackets after the . ! ? are skipped: ." .) ?"), and after a newline. `before` is the text
/// before the cursor (nil when the host gives none).
public func shouldAutoShift(before: String?, autocapitalization: Autocapitalization) -> Bool {
    guard let before, let last = before.last else { return autocapitalization != .none }
    switch autocapitalization {
    case .none: return false
    case .allCharacters: return true
    case .words: return last.isWhitespace
    case .sentences:
        if last.isNewline { return true }
        guard last == " " else { return false }
        let closers: Set<Character> = [")", "]", "}", "\"", "'", "\u{201D}", "\u{2019}", "\u{BB}"]
        guard let end = before.reversed().drop(while: { $0 == " " }).first(where: { !closers.contains($0) }) else { return true }
        return ".!?".contains(end) || end.isNewline
    }
}

/// SPEC 5.2 double-space period: a second space right after a letter or digit plus space becomes ". ".
/// `before` is the text before the cursor, ending with the first space.
public func doubleSpaceBecomesPeriod(before: String) -> Bool {
    let chars = before.suffix(2)
    guard chars.count == 2, chars.last == " ", let prev = chars.first else { return false }
    return prev.isLetter || prev.isNumber
}

/// What a space does (SPEC 5.2, 8.7).
public enum SpaceEdit: Sendable {
    /// Insert a space.
    case space
    /// Delete the space before the cursor and insert ". " (double-space period).
    case period
    /// Insert nothing: an auto-space is already there. It still counts as the first space of a
    /// double-space period.
    case nothing
}

/// The space key's edit: a double-space period when the setting is on, the last key was a space
/// and `doubleSpaceBecomesPeriod`; else nothing right after an auto-space (a suggestion tap, an
/// autocorrect, punctuation's own ". "); else a space.
public func spaceEdit(before: String, afterAutoSpace: Bool, lastKeyWasSpace: Bool, doubleSpacePeriod: Bool) -> SpaceEdit {
    if doubleSpacePeriod, lastKeyWasSpace, doubleSpaceBecomesPeriod(before: before) { return .period }
    return afterAutoSpace && !lastKeyWasSpace ? .nothing : .space
}

/// SPEC 5.2 backspace hold: repeat after 0.5 s, characters every 0.1 s for the first 5 repeats, then
/// every 0.06 s; from repeat 15 on, whole words every 0.15 s (slower, against overshoot).
public enum BackspaceRepeat {
    public static let delay: TimeInterval = 0.5
    static let slowRepeats = 5
    static let charRepeats = 15

    /// Whether repeat number `n` (0-based, after the initial delay) deletes a word.
    public static func deletesWord(repeat n: Int) -> Bool { n >= charRepeats }

    /// The wait between repeat `n` and the next one.
    public static func interval(afterRepeat n: Int) -> TimeInterval {
        deletesWord(repeat: n + 1) ? 0.15 : n < slowRepeats ? 0.1 : 0.06
    }

    /// Characters to delete for one word step: trailing whitespace plus the word before it (at least 1).
    public static func wordLength(before: String) -> Int {
        let spaces = before.reversed().prefix { $0.isWhitespace }.count
        let word = before.dropLast(spaces).reversed().prefix { !$0.isWhitespace }.count
        return max(1, spaces + word)
    }
}

/// SPEC 5.2 space-bar trackpad: a drag past 12 pt or a 0.4 s hold starts it, then the cursor moves
/// one character per 9 pt for a slow finger (up to 100 pt/s), down to one per 3.6 pt for a fast one
/// (600 pt/s and up), linear in between.
public struct Trackpad: Sendable {
    public static let startDistance: Double = 12
    static let slowPointsPerChar: Double = 9
    static let fastPointsPerChar: Double = 3.6
    static let slowSpeed: Double = 100
    static let fastSpeed: Double = 600

    private var anchor: Double
    private let direction: Double
    private var last: (x: Double, time: TimeInterval)?
    /// Until the cursor moves, the press is still a tap (a slow one, or one whose finger slid a
    /// little), however the trackpad started: rollover commits its space, and so does its release.
    public private(set) var movedCursor = false

    /// `startX` is where the finger is when the trackpad starts. `rightToLeft` flips the direction so
    /// a rightward drag moves the cursor right in Arabic text.
    public init(startX: Double, rightToLeft: Bool) {
        anchor = startX
        direction = rightToLeft ? -1 : 1
    }

    /// Points per character at a finger speed in pt/s.
    static func pointsPerChar(speed: Double) -> Double {
        let t = min(max((speed - slowSpeed) / (fastSpeed - slowSpeed), 0), 1)
        return slowPointsPerChar - t * (slowPointsPerChar - fastPointsPerChar)
    }

    /// The character offset to apply for the finger now at `x` at `time`, since the last call. The
    /// speed is the finger's since the last call (the first call counts as slow); what is left over
    /// carries to the next call, so slow drags step exactly every 9 pt.
    public mutating func offset(toX x: Double, at time: TimeInterval) -> Int {
        let speed = last.map { time > $0.time ? abs(x - $0.x) / (time - $0.time) : 0 } ?? 0
        last = (x, time)
        let perChar = Self.pointsPerChar(speed: speed)
        let steps = ((x - anchor) / perChar).rounded(.towardZero)
        anchor += steps * perChar
        if steps != 0 { movedCursor = true }
        return Int(steps * direction)
    }
}

/// SPEC 5.2 long-press strip: its items, visual left to right, and the one preselected. A top-row
/// digit comes first, and is preselected only where its hint is drawn; elsewhere the letter is in the
/// strip too (right after the digit, unless its alternates hold it) and is preselected, so a slow
/// press types the letter the key shows. Nil when the key has no strip.
public func longPressStrip(output: String, hint: String?, alternates: [String], hintShown: Bool) -> (items: [String], selected: Int)? {
    guard let hint else {
        guard !alternates.isEmpty else { return nil }
        return (alternates, alternates.firstIndex(of: output) ?? 0)
    }
    if hintShown { return ([hint] + alternates, 0) }
    let letters = alternates.contains(output) ? alternates : [output] + alternates
    return ([hint] + letters, 1 + (letters.firstIndex(of: output) ?? 0))
}

/// SPEC 5.2 bar band: the top row reaches into the bar's bottom edge, except over something the bar
/// can pick when the touch doesn't come mid-typing.
public enum BarBand {
    /// UI timing, not a tunable: mid-typing top-row taps land high, a bar tap usually follows a pause.
    public static let typingWindow: TimeInterval = 0.4

    /// Whether a touch in the band goes to the top row: always where the bar has nothing to pick right
    /// above it (an empty slot, the clipboard and emoji buttons), else only when the last key
    /// touch-down was under `typingWindow` before it (nil: none yet).
    public static func belongsToKeys(barTarget: Bool, sinceKeyDown: TimeInterval?) -> Bool {
        guard barTarget else { return true }
        guard let sinceKeyDown else { return false }
        return sinceKeyDown < typingWindow
    }
}

/// SPEC 5.2 system cancels (an edge gesture, a banner): a letter that was really pressed still counts.
public enum CancelledTouch {
    public static let minDuration: TimeInterval = 0.03

    /// Whether a cancelled press commits like a touch-up: a char key with no strip open, held at least `minDuration`.
    public static func commits(isChar: Bool, stripOpen: Bool, heldFor: TimeInterval) -> Bool {
        isChar && !stripOpen && heldFor >= minDuration
    }
}

/// SPEC 5.2 backspace swipe: a leftward drag past 12 pt deletes whole words, one more per 22 pt.
public enum BackspaceSwipe {
    public static let startDistance: Double = 12
    static let pointsPerWord: Double = 22

    /// Words deleted with the finger `dx` points left of where it went down (negative is right).
    public static func words(left dx: Double) -> Int {
        dx <= startDistance ? 0 : Int((dx - startDistance) / pointsPerWord) + 1
    }
}

/// SPEC 5.2 swipe down to hide: strict, so fast typing never triggers it.
public enum SwipeDownHide {
    static let minDown: Double = 70
    static let maxSideways: Double = 30
    static let maxDuration: TimeInterval = 0.3

    /// A touch that went down on a letter in `startRow` (0 is the top row) and has since moved
    /// `dx`, `dy` points (down is positive) over `elapsed` seconds.
    public static func triggers(startRow: Int, dx: Double, dy: Double, elapsed: TimeInterval) -> Bool {
        startRow <= 1 && dy >= minDown && abs(dx) < maxSideways && elapsed <= maxDuration
    }
}

/// SPEC 5.2 sudden moves: when one finger lifts as another lands, the touch screen can report the
/// two taps as one touch that jumps to the second key (LatinIME's "phantom sudden move": "quick
/// successive touches may be reported as a sudden move by touch panel firmware"). A finger at rest
/// never covers 0.6 of a key in one touch sample (about 2,800 pt/s at 120 Hz; a thumb rolling off a
/// key as it lifts moves far less), so that step is a lift and a new touch-down. A finger already
/// moving fast (a flick, a quick drag) is left alone.
public enum SuddenMove {
    /// In key widths.
    static let minStep: Double = 0.6
    /// A finger whose previous step was this long (in key widths) was moving fast...
    static let fastStep: Double = 0.25
    /// ...unless that step came this long before: samples come every 8 ms at 120 Hz, so a finger
    /// with none for 20 ms was at rest.
    static let restAfter: TimeInterval = 0.02

    /// Whether a step of `step` points between two samples is a new touch, after a previous step of
    /// `stepBefore` points `interval` seconds before it.
    public static func isNewTouch(step: Double, stepBefore: Double, interval: TimeInterval, keyWidth: Double) -> Bool {
        let movingFast = stepBefore >= fastStep * keyWidth && interval < restAfter
        return step >= minStep * keyWidth && !movingFast
    }
}
