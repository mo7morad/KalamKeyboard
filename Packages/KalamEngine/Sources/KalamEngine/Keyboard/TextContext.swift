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
