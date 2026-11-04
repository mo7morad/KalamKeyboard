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

/// SPEC 5.2 space-bar trackpad: a drag past 12 pt starts it, then the cursor moves one character per 9 pt.
public struct Trackpad: Sendable {
    public static let startDistance: Double = 12
    static let pointsPerChar: Double = 9

    private var anchor: Double
    private let direction: Double

    /// `rightToLeft` flips the direction so a rightward drag moves the cursor right in Arabic text.
    public init(startX: Double, rightToLeft: Bool) {
        anchor = startX
        direction = rightToLeft ? -1 : 1
    }

    /// The character offset to apply for the finger now at `x`, since the last call.
    public mutating func offset(toX x: Double) -> Int {
        let steps = ((x - anchor) / Self.pointsPerChar).rounded(.towardZero)
        anchor += steps * Self.pointsPerChar
        return Int(steps * direction)
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
