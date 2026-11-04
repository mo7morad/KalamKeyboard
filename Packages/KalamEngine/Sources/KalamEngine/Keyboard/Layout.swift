import Foundation

/// A keyboard page (SPEC 5.1), built from docs/reference/apple. Key widths are in key units (1.0 = one
/// letter key pitch of this page). Rows are in visual left-to-right order, Arabic included.
public struct Layout: Codable, Sendable {
    public let id: String
    public let lang: Lang
    public let rows: [[Key]]
    /// SPEC 5.1: row 0 is the optional digit row, outside the page's key units.
    public private(set) var hasNumberRow = false

    enum CodingKeys: String, CodingKey { case id, lang, rows }

    public struct Key: Codable, Sendable {
        /// `gap` is blank space (Apple's EN row 3 and AR row 3). For `page` keys, `output` names the
        /// target page ("letters", "numbers", "symbols").
        public enum Kind: String, Codable, Sendable { case char, shift, backspace, space, `return`, globe, lang, page, gap }

        public let id: String
        public let label: String
        public let output: String
        public let width: Double
        public let kind: Kind
        /// Long-press strip, visual left to right, including the key's own output.
        public let alternates: [String]
        public let popup: Bool
        /// Small top-row digit, drawn in the corner and preselected in the long-press strip.
        public let hint: String?

        enum CodingKeys: String, CodingKey { case id, label, output, width, kind, alternates, popup, hint }

        /// Only `id` and `label` are required: output defaults to the label, width to 1,
        /// kind to char, and only char keys pop up by default.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            label = try c.decode(String.self, forKey: .label)
            output = try c.decodeIfPresent(String.self, forKey: .output) ?? label
            width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 1
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .char
            alternates = try c.decodeIfPresent([String].self, forKey: .alternates) ?? []
            popup = try c.decodeIfPresent(Bool.self, forKey: .popup) ?? (kind == .char)
            hint = try c.decodeIfPresent(String.self, forKey: .hint)
        }

        init(id: String, label: String, output: String, width: Double, kind: Kind,
             alternates: [String] = [], popup: Bool = false, hint: String? = nil) {
            (self.id, self.label, self.output, self.width, self.kind) = (id, label, output, width, kind)
            (self.alternates, self.popup, self.hint) = (alternates, popup, hint)
        }

        func resized(by delta: Double) -> Key {
            Key(id: id, label: label, output: output, width: width + delta, kind: kind, alternates: alternates, popup: popup, hint: hint)
        }
    }

    /// A layout bundled in the package, e.g. "en-letters".
    public static func bundled(_ id: String) -> Layout? {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Layouts"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Layout.self, from: data)
    }

    /// The width of the widest row, in key units (the number row is fitted to it).
    public var widestRow: Double { letterRows.map(Self.width).max() ?? 0 }

    /// The page's own rows, without the number row.
    private var letterRows: ArraySlice<[Key]> { rows.dropFirst(hasNumberRow ? 1 : 0) }

    static func width(_ row: [Key]) -> Double { row.reduce(0) { $0 + $1.width } }

    /// SPEC 5.2: when iOS asks for our own globe key, it goes left of the EN/AR key, and the space
    /// bar gives up the room.
    public func withGlobeKey() -> Layout {
        let rows = rows.map { row -> [Key] in
            guard let lang = row.firstIndex(where: { $0.kind == .lang }),
                  let space = row.firstIndex(where: { $0.kind == .space }) else { return row }
            let globe = Key(id: "globe", label: "", output: "", width: row[lang].width, kind: .globe)
            var out = row
            out[space] = row[space].resized(by: -globe.width)
            out.insert(globe, at: lang)
            return out
        }
        return Layout(id: id, lang: lang, rows: rows, hasNumberRow: hasNumberRow)
    }

    /// SPEC 5.1 number row: `digits` as a top row of plain keys spanning the widest row. The old top
    /// row loses its digit hints, so it draws none and its long-press strip doesn't offer them.
    public func withNumberRow(digits: [String]) -> Layout {
        guard !hasNumberRow, !digits.isEmpty else { return self }
        let width = widestRow / Double(digits.count)
        let numberRow = digits.map { Key(id: $0, label: $0, output: $0, width: width, kind: .char, popup: true) }
        let rows = rows.enumerated().map { r, row in
            r > 0 ? row : row.map { Key(id: $0.id, label: $0.label, output: $0.output, width: $0.width, kind: $0.kind, alternates: $0.alternates, popup: $0.popup) }
        }
        return Layout(id: id, lang: lang, rows: [numberRow] + rows, hasNumberRow: true)
    }

    /// Every digit on the page as Eastern Arabic (١٢٣) or Western (123), for the Arabic pages'
    /// easternArabicDigits setting: the 123 page, the top-row hints and their long-press picks.
    public func withDigits(eastern: Bool) -> Layout {
        func convert(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
                let (from, to): (UInt32, UInt32) = eastern ? (0x30, 0x660) : (0x660, 0x30)
                guard (from...from + 9).contains(scalar.value) else { return scalar }
                return Unicode.Scalar(scalar.value - from + to) ?? scalar
            }))
        }
        let rows = rows.map { row in
            row.map { key in
                Key(id: convert(key.id), label: convert(key.label), output: convert(key.output), width: key.width, kind: key.kind,
                    alternates: key.alternates.map(convert), popup: key.popup, hint: key.hint.map(convert))
            }
        }
        return Layout(id: id, lang: lang, rows: rows, hasNumberRow: hasNumberRow)
    }

    /// Char key output -> key center in key units. x counts key widths from the left edge of the
    /// widest row (narrower rows are centered); y counts rows, so row 0 centers at y = 0.5. The number
    /// row isn't counted: tap points stay in the page's own key units (SPEC 5.2).
    public func keyCenters() -> [String: Point] {
        var centers: [String: Point] = [:]
        for (y, row) in letterRows.enumerated() {
            var x = (widestRow - Self.width(row)) / 2
            for key in row {
                if key.kind == .char { centers[key.output] = Point(x: x + key.width / 2, y: Double(y) + 0.5) }
                x += key.width
            }
        }
        return centers
    }
}

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
