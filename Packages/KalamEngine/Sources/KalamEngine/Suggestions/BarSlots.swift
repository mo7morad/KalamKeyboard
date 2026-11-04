import Foundation

/// One suggestion bar slot (SPEC 5.4).
public struct BarSlot: Equatable, Sendable {
    public let word: String  // what a tap inserts
    public let label: String  // what the bar shows: the word, or the quoted literal
    public let ident: String
    public let bold: Bool
    public let isLiteral: Bool
}

/// The three bar slots in visual left-to-right order: EN [alt1] [primary] [alt2], AR mirrored.
/// With a pending autocorrect, the primary is it, in bold, and alt1 is the quoted literal;
/// otherwise the slots hold the first three candidates (or predictions). Nil is an empty slot.
public func barSlots(_ candidates: [Suggestion], autocorrect: Suggestion?, literal: String, lang: Lang,
                     capitalized: Bool) -> [BarSlot?] {
    func slot(_ s: Suggestion, bold: Bool = false) -> BarSlot {
        let word = cased(s.text, capitalized: capitalized)
        return BarSlot(word: word, label: word, ident: s.ident, bold: bold, isLiteral: s.isLiteral)
    }
    var seen: Set<String> = []
    let unique = candidates.filter { seen.insert($0.text).inserted }
    var primary: BarSlot?, alt1: BarSlot?, alt2: BarSlot?
    if let autocorrect, let typed = unique.first(where: \.isLiteral) {
        primary = slot(autocorrect, bold: true)
        alt1 = BarSlot(word: literal, label: "\u{201C}\(literal)\u{201D}", ident: typed.ident, bold: false, isLiteral: true)
        alt2 = unique.first { !$0.isLiteral && $0.ident != autocorrect.ident }.map { slot($0) }
    } else {
        let top = unique.prefix(3).map { slot($0) }
        (primary, alt1, alt2) = (top.first, top.dropFirst().first, top.dropFirst(2).first)
    }
    return lang == .en ? [alt1, primary, alt2] : [alt2, primary, alt1]
}
