import Foundation

/// Shift and caps lock (SPEC 5.2): a tap shifts one letter, a second tap within 0.3 s locks caps.
public struct ShiftState: Sendable {
    public enum Mode: Sendable { case off, once, locked }

    static let doubleTapWindow: TimeInterval = 0.3

    public private(set) var mode: Mode = .off
    private var lastTap: TimeInterval?

    public init() {}

    public mutating func tap(at time: TimeInterval) {
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

    /// A letter was typed: a one-shot shift ends.
    public mutating func letterTyped() {
        if mode == .once { mode = .off }
    }

    /// Auto-shift (SPEC 8.6) sets or clears a one-shot shift, and never touches caps lock.
    public mutating func setAuto(_ on: Bool) {
        if mode != .locked { mode = on ? .once : .off }
    }
}

/// Mirrors UITextAutocapitalizationType without importing UIKit.
public enum Autocapitalization: Sendable { case none, words, sentences, allCharacters }

/// SPEC 8.6 auto-shift: at the start of the field, after a sentence end plus space, and after a
/// newline. `before` is the text before the cursor (nil when the host gives none).
public func shouldAutoShift(before: String?, autocapitalization: Autocapitalization) -> Bool {
    guard let before, let last = before.last else { return autocapitalization != .none }
    switch autocapitalization {
    case .none: return false
    case .allCharacters: return true
    case .words: return last.isWhitespace
    case .sentences:
        if last.isNewline { return true }
        guard last == " " else { return false }
        guard let end = before.reversed().first(where: { $0 != " " }) else { return true }
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

/// SPEC 5.2 backspace hold: repeat after 0.45 s every 0.09 s; after 15 repeats delete whole words.
public enum BackspaceRepeat {
    public static let delay: TimeInterval = 0.45
    public static let interval: TimeInterval = 0.09
    static let charRepeats = 15

    /// Whether repeat number `n` (0-based, after the initial delay) deletes a word.
    public static func deletesWord(repeat n: Int) -> Bool { n >= charRepeats }

    /// Characters to delete for one word step: trailing whitespace plus the word before it (at least 1).
    public static func wordLength(before: String) -> Int {
        let spaces = before.reversed().prefix { $0.isWhitespace }.count
        let word = before.dropLast(spaces).reversed().prefix { !$0.isWhitespace }.count
        return max(1, spaces + word)
    }
}

/// SPEC 5.2 space-bar trackpad: a drag past 12 pt or a 0.4 s hold starts it, then the cursor moves
/// one character per 9 pt.
public struct Trackpad: Sendable {
    public static let startDistance: Double = 12
    static let pointsPerChar: Double = 9

    private var anchor: Double
    private let direction: Double
    private let fromHold: Bool
    private var moved = false

    /// `downX` is where the finger went down on space. `rightToLeft` flips the direction so a
    /// rightward drag moves the cursor right in Arabic text.
    public init(startX: Double, downX: Double, rightToLeft: Bool) {
        anchor = startX
        direction = rightToLeft ? -1 : 1
        fromHold = abs(startX - downX) <= Self.startDistance
    }

    /// The character offset to apply for the finger now at `x`, since the last call.
    public mutating func offset(toX x: Double) -> Int {
        let steps = ((x - anchor) / Self.pointsPerChar).rounded(.towardZero)
        anchor += steps * Self.pointsPerChar
        if steps != 0 { moved = true }
        return Int(steps * direction)
    }

    /// A hold that never moved the cursor was a slow tap: its release types a space.
    public var releaseTypesSpace: Bool { fromHold && !moved }
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

/// SPEC 5.2 bar band: the top row reaches into the bar's bottom edge during a typing burst only.
public enum BarBand {
    /// UI timing, not a tunable: mid-typing top-row taps land high, a bar tap usually follows a pause.
    public static let typingWindow: TimeInterval = 0.4

    /// Whether a touch in the band goes to the top row: always while the bar has nothing to tap,
    /// else only when the last key touch-down was under `typingWindow` before it (nil: none yet).
    public static func belongsToKeys(barTappable: Bool, sinceKeyDown: TimeInterval?) -> Bool {
        guard barTappable else { return true }
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
