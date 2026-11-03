import Foundation

public struct Token: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case en, ar, tok, sentenceEnd }
    public let surface: String
    public let kind: Kind

    public init(_ surface: String, _ kind: Kind) {
        self.surface = surface
        self.kind = kind
    }

    public var ident: String { KalamEngine.ident(surface, kind: kind) }
}

/// The n-gram identity (SPEC 6.3). EN: lowercased, curly apostrophes made straight (wordfreq has
/// "don't", not "don’t"). AR: without tashkeel and tatweel. tok: unchanged.
public func ident(_ surface: String, kind: Token.Kind) -> String {
    switch kind {
    case .en:
        return String(String.UnicodeScalarView(surface.lowercased().unicodeScalars.map { apostrophes.contains($0) ? "'" : $0 }))
    case .ar:
        return String(String.UnicodeScalarView(surface.unicodeScalars.filter { !isTashkeel($0) && !isTatweel($0) }))
    case .tok, .sentenceEnd:
        return surface
    }
}

public let sentenceStart = "<s>"

/// Splits text into words, special tokens and sentence ends (SPEC 6.2).
public func tokenize(_ text: String) -> [Token] {
    var tokens: [Token] = []
    for (lineIndex, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
        if lineIndex > 0 { endSentence(&tokens) }
        for chunk in line.split(whereSeparator: \.isWhitespace) {
            let core = chunk.trimmingCharacters(in: wrappers)
            if isSpecial(core) {
                tokens.append(Token(core, .tok))
                let trailing = chunk.reversed().prefix { !$0.isLetter && !$0.isNumber }
                if trailing.contains(where: { $0.unicodeScalars.contains(where: isSentenceEnd) }) {
                    endSentence(&tokens)
                }
            } else {
                scanWords(Array(chunk.unicodeScalars), into: &tokens)
            }
        }
    }
    return tokens
}

/// Engine context for the text before the cursor: the last 2 idents of the current sentence,
/// with <s> standing in for the sentence start (SPEC 8.1, 8.6).
public func contextIdents(_ text: String) -> [String] {
    let tokens = tokenize(text)
    let start = tokens.lastIndex { $0.kind == .sentenceEnd }.map { $0 + 1 } ?? 0
    let sentence = tokens[start...]
    return Array(([sentenceStart] + sentence.map(\.ident)).suffix(2))
}

private let wrappers = CharacterSet(charactersIn: ".,!?;:()[]{}\"'«»…،؛؟")

private func isSentenceEnd(_ s: Unicode.Scalar) -> Bool {
    s == "." || s == "!" || s == "?" || s == "\u{061F}"
}

private func endSentence(_ tokens: inout [Token]) {
    if let last = tokens.last, last.kind != .sentenceEnd { tokens.append(Token("", .sentenceEnd)) }
}

private func isSpecial(_ s: String) -> Bool {
    if s.count > 1, s.first == "@" || s.first == "#" {
        return s.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
    if s.contains("://") || s.lowercased().hasPrefix("www.") { return true }
    let parts = s.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, let dot = parts[1].firstIndex(of: ".") else { return false }
    return dot != parts[1].startIndex && dot != parts[1].index(before: parts[1].endIndex)
}

private func isEnglish(_ s: Unicode.Scalar) -> Bool { s.isASCII && s.properties.isAlphabetic || isDigit(s) }
private func isDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }
private func isArabicLetter(_ s: Unicode.Scalar) -> Bool { (0x0621...0x064A).contains(s.value) || s.value == 0x0671 }
private func isTashkeel(_ s: Unicode.Scalar) -> Bool { (0x064B...0x065F).contains(s.value) || s.value == 0x0670 }
private func isTatweel(_ s: Unicode.Scalar) -> Bool { s.value == 0x0640 }

private func scanWords(_ scalars: [Unicode.Scalar], into tokens: inout [Token]) {
    var i = 0
    while i < scalars.count {
        let start = i
        if isEnglish(scalars[i]) {
            var hasLetter = false
            while i < scalars.count {
                if isEnglish(scalars[i]) {
                    hasLetter = hasLetter || !isDigit(scalars[i])
                    i += 1
                } else if apostrophes.contains(scalars[i]), i + 1 < scalars.count, isEnglish(scalars[i + 1]) {
                    i += 1
                } else {
                    break
                }
            }
            if hasLetter { tokens.append(Token(String(String.UnicodeScalarView(scalars[start..<i])), .en)) }
        } else if isArabicLetter(scalars[i]) {
            var surface = String.UnicodeScalarView()
            while i < scalars.count, isArabicLetter(scalars[i]) || isTashkeel(scalars[i]) {
                if !isTashkeel(scalars[i]) && !isTatweel(scalars[i]) { surface.append(scalars[i]) }
                i += 1
            }
            tokens.append(Token(String(surface), .ar))
        } else {
            if isSentenceEnd(scalars[i]) { endSentence(&tokens) }
            i += 1
        }
    }
}
