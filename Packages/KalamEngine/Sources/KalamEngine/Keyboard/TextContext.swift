import Foundation

// Pure typing rules for the keyboard's input state (SPEC 8.1, 5.4, 8.6, 8.7). No UIKit here.

/// Whether `char` continues the current word `word` rather than ending it. Letters, digits and
/// marks always do; an apostrophe does inside a word (don't); @ # _ start or continue a special
/// token, and a dot continues an email (me@x.com).
public func continuesWord(_ char: String, word: String) -> Bool {
    guard let c = char.first, char.count == 1 else { return false }
    if c.isLetter || c.isNumber || c.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .nonspacingMark }) { return true }
    if "@#_".contains(c) { return true }
    if c == "'" || c == "\u{2019}" { return !word.isEmpty }
    return c == "." && word.contains("@")
}

/// The word being typed: the trailing run of word characters before the cursor.
public func currentWord(before text: String) -> String {
    // Scanning back, word "@" lets apostrophes and dots through; a dot then splits the word unless it's an email.
    var word = String(text.reversed().prefix { continuesWord(String($0), word: "@") }.reversed())
    if !word.contains("@"), let dot = word.lastIndex(of: ".") { word = String(word[word.index(after: dot)...]) }
    return String(word.drop { $0 == "'" || $0 == "\u{2019}" })
}

/// The rest of the word after the cursor: the leading run of word characters, without a closing
/// apostrophe (SPEC 5.4: a suggestion tap replaces the whole word around the cursor).
public func currentWordTail(after text: String) -> String {
    var tail = String(text.prefix { continuesWord(String($0), word: "a") })
    while tail.last == "'" || tail.last == "\u{2019}" { tail.removeLast() }
    return tail
}

/// SPEC 8.5 rule 3: whether the whitespace-delimited run that ends at the cursor has @ / . : \ or
/// an emoji before the word's last letters (www.goo, a/b, e.g, x@y), so the word is no word to correct.
public func insideNonWordToken(before text: String) -> Bool {
    let run = text.reversed().prefix { !$0.isWhitespace }
    return run.drop { $0.isLetter || $0.isNumber }.contains { c in
        "@/.:\\".contains(c) || c.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0 == "\u{FE0F}" }
    }
}

/// Engine context for the text before the cursor: the last 2 words before the current word,
/// with <s> after . ! ? ؟, a newline or at an empty field.
public func contextWords(before text: String) -> [String] {
    contextIdents(String(text.dropLast(currentWord(before: text).count)))
}

/// The taps for `word` after the text changed under the keyboard: the taps that still spell its
/// start keep their points, and the rest of its characters become point-less taps.
public func resyncedTaps(_ taps: [Tap], to word: String) -> [Tap] {
    var kept: [Tap] = []
    var spelled = ""
    for tap in taps {
        guard word.hasPrefix(spelled + tap.char) else { break }
        spelled += tap.char
        kept.append(tap)
    }
    return kept + word.dropFirst(spelled.count).map { Tap(String($0)) }
}

/// SPEC 8.6 display casing: a capital first letter, unless the form already carries its own
/// casing (Moe's or the corpus's: iPhone, London).
public func cased(_ word: String, capitalized: Bool) -> String {
    guard capitalized, word == word.lowercased(), let first = word.first else { return word }
    return first.uppercased() + word.dropFirst()
}

/// SPEC 8.7 punctuation spacing: what to delete before the cursor and what to insert when `char`
/// is typed. After an auto-space, . , ! ? ; ، ؛ ؟ take its place and bring their own space, and
/// : ' " ) just take its place.
public func punctuationEdit(_ char: String, afterAutoSpace: Bool) -> (delete: Int, insert: String) {
    guard afterAutoSpace else { return (0, char) }
    if [".", ",", "!", "?", ";", "،", "؛", "؟"].contains(char) { return (1, char + " ") }
    if [":", "'", "\"", ")", "\u{2019}", "\u{201D}"].contains(char) { return (1, char) }
    return (0, char)
}

/// . ! ? ؟ and newline end a sentence (SPEC 8.6, 9.2).
public func endsSentence(_ char: String) -> Bool {
    [".", "!", "?", "؟", "\n"].contains(char)
}

/// SPEC 5.2 trackpad direction, from the text at the cursor: the nearest strong-direction letter
/// before it (Arabic script is right to left, any other letter left to right), else the nearest
/// after it. Spaces, digits, punctuation, emoji and marks don't count. Nil when there is none.
public func textIsRightToLeft(before: String?, after: String?) -> Bool? {
    func direction<S: Sequence>(_ scalars: S) -> Bool? where S.Element == Unicode.Scalar {
        scalars.lazy.compactMap(strongDirection).first
    }
    return direction((before ?? "").unicodeScalars.reversed()) ?? direction((after ?? "").unicodeScalars)
}

/// True for an Arabic-script letter, false for any other letter, nil otherwise.
func strongDirection(_ scalar: Unicode.Scalar) -> Bool? {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
        let arabic: [ClosedRange<UInt32>] = [0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF]
        return arabic.contains { $0.contains(scalar.value) }
    default: return nil
    }
}

/// SPEC 8.5 undo slot: an autocorrect plus the tail its commit inserted after the replacement (an
/// auto-space, punctuation, a newline). Backspaces first delete the tail as usual; the one that
/// reaches the replacement restores the literal, taking an auto-space with it.
public struct AutocorrectUndo: Sendable {
    public enum Step: Equatable, Sendable {
        /// Delete `delete` characters and insert the literal; the slot is used up.
        case revert(delete: Int, insert: String)
        /// A plain one-character backspace; the slot stays.
        case delete
        /// The text no longer ends with the replacement and its tail: a plain backspace, no slot.
        case gone
    }

    public let literal: String
    /// The literal's taps, restored with it.
    public let taps: [Tap]
    public let replacement: String
    public private(set) var tail = ""

    public init(literal: String, taps: [Tap], replacement: String) {
        (self.literal, self.taps, self.replacement) = (literal, taps, replacement)
    }

    /// The slot after the commit's key deleted `deleting` characters of the tail (punctuation taking
    /// an auto-space's place) and inserted `text`. Nil when the delete reaches past the tail.
    public func typed(_ text: String, deleting: Int = 0) -> AutocorrectUndo? {
        guard deleting <= tail.count else { return nil }
        var next = self
        next.tail = String(tail.dropLast(deleting)) + text
        return next
    }

    /// One backspace with `before` the text before the cursor.
    public mutating func backspace(before: String) -> Step {
        guard before.hasSuffix(replacement + tail) else { return .gone }
        if tail.isEmpty || tail == " " { return .revert(delete: replacement.count + tail.count, insert: literal) }
        tail.removeLast()
        return .delete
    }
}

/// SPEC 8.5 revert memory: the session's recent autocorrects, each with the text before the word it
/// replaced (its last contextLength characters), so that retyping the literal there, or tapping the
/// corrected word for its original (5.4), reverts it.
public struct RecentAutocorrects: Sendable {
    public struct Entry: Equatable, Sendable {
        public let literal: String
        public let replacement: String
        let before: String
    }

    static let capacity = 10
    static let contextLength = 32
    private var entries: [Entry] = []

    public init() {}

    /// `literal` was autocorrected to `replacement`, with `before` the text before it.
    public mutating func add(literal: String, replacement: String, before: String) {
        entries.append(Entry(literal: literal, replacement: replacement, before: String(before.suffix(Self.contextLength))))
        if entries.count > Self.capacity { entries.removeFirst() }
    }

    /// The autocorrect that a commit of `literal` after `before` retypes.
    public func retyped(_ literal: String, before: String) -> Entry? {
        let before = String(before.suffix(Self.contextLength))
        return entries.last { $0.literal == literal && $0.before == before }
    }

    /// The autocorrect whose replacement is the whole word around the cursor, with `before` and
    /// `after` the text on each side of it. Nil unless the cursor is in or right after a word.
    public func corrected(before: String, after: String) -> Entry? {
        let head = currentWord(before: before)
        guard !head.isEmpty else { return nil }
        let word = head + currentWordTail(after: after)
        let prefix = String(before.dropLast(head.count).suffix(Self.contextLength))
        return entries.last { $0.replacement == word && $0.before == prefix }
    }

    public mutating func remove(_ entry: Entry) {
        entries.removeAll { $0 == entry }
    }
}
