import Foundation

/// A keyboard page (SPEC 5.1). Key widths are in key units (1.0 = one standard letter key).
public struct Layout: Codable, Sendable {
    public let id: String
    public let lang: Lang
    public let rows: [[Key]]

    public struct Key: Codable, Sendable {
        public enum Kind: String, Codable, Sendable { case char, shift, backspace, space, `return`, globe, lang, page }

        public let id: String
        public let label: String
        public let output: String
        public let width: Double
        public let kind: Kind
        public let alternates: [String]
        public let popup: Bool

        enum CodingKeys: String, CodingKey { case id, label, output, width, kind, alternates, popup }

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
        }
    }

    /// A layout bundled in the package, e.g. "en-letters".
    public static func bundled(_ id: String) -> Layout? {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Layouts"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Layout.self, from: data)
    }

    /// Char key output -> key center in key units. x counts key widths from the left edge of the
    /// widest row (narrower rows are centered); y counts rows, so row 0 centers at y = 0.5.
    public func keyCenters() -> [String: Point] {
        let rowWidths = rows.map { $0.reduce(0) { $0 + $1.width } }
        let widest = rowWidths.max() ?? 0
        var centers: [String: Point] = [:]
        for (y, row) in rows.enumerated() {
            var x = (widest - rowWidths[y]) / 2
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
