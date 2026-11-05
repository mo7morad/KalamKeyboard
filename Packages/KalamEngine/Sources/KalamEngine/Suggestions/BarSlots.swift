import Foundation

/// One suggestion bar slot (SPEC 5.4).
public struct BarSlot: Equatable, Sendable {
    public let word: String  // what a tap inserts
    public let label: String  // what the bar shows: the word, or the quoted literal
    public let ident: String
    public let bold: Bool
    public let isLiteral: Bool
    /// SPEC 5.6: replaces the word but is never learned, blocked or autocorrected to.
    public var isEmoji = false
    /// SPEC 5.4 tap to revert: the original literal of the corrected word around the cursor.
    public var isRevert = false
    /// SPEC 5.4 wrong-layout rescue: the slot's word is of this (the other) language; a long-press blocks it there.
    public var rescueLang: Lang?
}

/// The three bar slots in visual left-to-right order: EN [alt1] [primary] [alt2], AR mirrored.
/// With a pending autocorrect, the primary is it, marked `bold` (the bar draws it on Apple's capsule), and alt1 is the quoted literal;
/// otherwise the slots hold the first three candidates (or predictions). Apple quotes the literal
/// with “ ” in English and straight " " in Arabic. An emoji for the word takes alt2, as Apple's
/// does (SPEC 5.6). `revert`, the original of the corrected word around the cursor, takes alt1,
/// unquoted, as Apple's revert offer does (SPEC 5.4). `rescue`, the other language's word for the same
/// spots (SPEC 5.4), takes alt2, or alt1 when the emoji holds alt2. In Arabic with no pending
/// autocorrect, the best other spelling of the literal's key takes alt1 when no slot shows it.
/// Candidates and the rescue are shown in `casing` (SPEC 8.6; all caps in caps lock, 5.4).
/// Nil is an empty slot.
public func barSlots(_ candidates: [Suggestion], autocorrect: Suggestion?, literal: String, lang: Lang,
                     casing: Casing, emoji: String? = nil, revert: String? = nil, rescue: Suggestion? = nil) -> [BarSlot?] {
    func slot(_ s: Suggestion, bold: Bool = false) -> BarSlot {
        let word = cased(s.text, casing)
        return BarSlot(word: word, label: word, ident: s.ident, bold: bold, isLiteral: s.isLiteral)
    }
    var seen: Set<String> = []
    let unique = candidates.filter { seen.insert($0.text).inserted }
    var primary: BarSlot?, alt1: BarSlot?, alt2: BarSlot?
    if let autocorrect, let typed = unique.first(where: \.isLiteral) {
        primary = slot(autocorrect, bold: true)
        let quoted = lang == .en ? "\u{201C}\(literal)\u{201D}" : "\"\(literal)\""
        alt1 = BarSlot(word: literal, label: quoted, ident: typed.ident, bold: false, isLiteral: true)
        alt2 = unique.first { !$0.isLiteral && $0.ident != autocorrect.ident }.map { slot($0) }
    } else {
        let top = unique.prefix(3).map { slot($0) }
        (primary, alt1, alt2) = (top.first, top.dropFirst().first, top.dropFirst(2).first)
    }
    if let emoji {
        alt2 = BarSlot(word: emoji, label: emoji, ident: emoji, bold: false, isLiteral: false, isEmoji: true)
    }
    if let rescue {
        let word = cased(rescue.text, casing)
        let rescued = BarSlot(word: word, label: word, ident: rescue.ident, bold: false, isLiteral: false, rescueLang: lang == .en ? .ar : .en)
        if emoji == nil { alt2 = rescued } else { alt1 = rescued }
    }
    let literalKey = normalize(literal, lang: lang)
    if lang == .ar, autocorrect == nil, alt1?.rescueLang == nil,
       let variant = unique.first(where: { !$0.isLiteral && normalize($0.ident, lang: lang) == literalKey }),
       ![primary, alt1, alt2].contains(where: { $0?.ident == variant.ident }) {
        alt1 = slot(variant)
    }
    if let revert {
        alt1 = BarSlot(word: revert, label: revert, ident: revert, bold: false, isLiteral: true, isRevert: true)
    }
    return lang == .en ? [alt1, primary, alt2] : [alt2, primary, alt1]
}
