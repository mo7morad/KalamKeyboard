import Foundation

public enum Lang: String, Codable, Sendable {
    case en, ar
}

private let arabicMap: [Unicode.Scalar: Unicode.Scalar] = [
    "\u{0623}": "\u{0627}", "\u{0625}": "\u{0627}", "\u{0622}": "\u{0627}", "\u{0671}": "\u{0627}",
    "\u{0649}": "\u{064A}", "\u{0629}": "\u{0647}", "\u{0624}": "\u{0648}", "\u{0626}": "\u{064A}",
    "\u{06A9}": "\u{0643}", "\u{06CC}": "\u{064A}",
]
let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}", "\u{2018}", "\u{02BC}"]

private func isArabicDropped(_ v: UInt32) -> Bool {
    switch v {
    case 0x0640, 0x0670, 0x200C...0x200F, 0x064B...0x065F, 0x06D6...0x06ED: return true
    default: return false
    }
}

/// Lookup key for a surface (SPEC 6.1). Iterates Unicode scalars; mirrors Tools/lexicon-builder/normalize.py.
public func normalize(_ text: String, lang: Lang) -> String {
    var out = String.UnicodeScalarView()
    switch lang {
    case .ar:
        for s in text.precomposedStringWithCanonicalMapping.unicodeScalars where !isArabicDropped(s.value) {
            out.append(arabicMap[s] ?? s)
        }
        return String(out)
    case .en:
        for s in text.decomposedStringWithCanonicalMapping.unicodeScalars
        where s.properties.canonicalCombiningClass == .notReordered && !apostrophes.contains(s) {
            out.append(s)
        }
        return String(out).lowercased()
    }
}
