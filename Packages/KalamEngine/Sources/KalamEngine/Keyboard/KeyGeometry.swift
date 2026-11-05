import CoreGraphics

/// Key frames in points for one page at a given width, from Apple's iPhone 17 metrics
/// (docs/reference/apple/README.md), tuned so the rendered caps land on Apple's pixels. Hit frames tile
/// each row with no gaps; caps are the drawn keys.
public struct KeyGeometry: Sendable {
    public struct Frame: Sendable {
        public let key: Layout.Key
        public let hit: CGRect
        public let cap: CGRect
        /// A digit key of the number row (SPEC 5.1): no tap point for the engine.
        public let inNumberRow: Bool
    }

    /// Hit area inset from the left and right edges.
    static let sideInset: CGFloat = 3.4
    /// Space between neighbouring caps.
    static let capGap: CGFloat = 6
    /// Key area top to the first hit row.
    static let topInset: CGFloat = 2
    /// The default keyboard height's row pitch, Apple's (SPEC 5.2).
    public static let rowPitch = CGFloat(KeyboardHeight.default.rowPitch)
    /// Hit row top to its caps. Moe's taps land about 7 pt above the caps' centers, so each row's
    /// hit band starts 5 pt above where Apple's gaps would put it (device round 2 trace).
    static let capTop: CGFloat = 6.1
    /// The pitch minus the cap height (Apple's 42.8 at 54).
    static let capShortfall: CGFloat = 11.2
    /// SPEC 5.2: with the number row on, the letters page's pitch shrinks this much.
    static let numberRowShrink: CGFloat = 4
    /// Touch band under the bottom row's caps (it maps to the bottom row). Without it, taps aimed
    /// where Apple's lower space bar sits fall into iOS's globe strip and are lost (device round 2).
    static let bottomInset: CGFloat = 4.5
    /// Height of the key area at the default setting, excluding the suggestion bar. Apple's is 226; a
    /// third-party keyboard gets a 17 pt taller globe strip below it on iOS 27, so the area is as short as it can be.
    public static let height = height(rows: 4, pitch: rowPitch)

    /// SPEC 5.2: the key area's height at a setting, the same on every page.
    public static func height(_ setting: KeyboardHeight, numberRow: Bool) -> CGFloat {
        let (rows, pitch) = letterRows(setting, numberRow: numberRow)
        return height(rows: rows, pitch: pitch)
    }

    /// The pitch that makes a page of `rows` rows fill that height: the letters page's pitch, or
    /// taller rows on the 123 and #+= pages when the number row is on.
    public static func rowPitch(_ setting: KeyboardHeight, numberRow: Bool, rows: Int) -> CGFloat {
        let (letterRows, pitch) = letterRows(setting, numberRow: numberRow)
        return pitch * CGFloat(letterRows) / CGFloat(max(rows, 1))
    }

    private static func letterRows(_ setting: KeyboardHeight, numberRow: Bool) -> (rows: Int, pitch: CGFloat) {
        numberRow ? (5, CGFloat(setting.rowPitch) - numberRowShrink) : (4, CGFloat(setting.rowPitch))
    }

    private static func height(rows: Int, pitch: CGFloat) -> CGFloat {
        topInset + CGFloat(rows - 1) * pitch + capTop + (pitch - capShortfall) + bottomInset
    }

    public let frames: [Frame]
    /// Points per key unit, horizontally.
    public let unit: CGFloat
    /// Points per key unit, vertically.
    public let pitch: CGFloat
    private let origin: CGPoint
    /// Rows above the page's own row 0 (the number row).
    private let rowOffset: CGFloat

    /// `origin` is the top-left of the key area in the caller's coordinates. Gap keys get no frame.
    public init(layout: Layout, width: CGFloat, origin: CGPoint = .zero, rowPitch: CGFloat = KeyGeometry.rowPitch) {
        let widest = layout.widestRow
        unit = (width - 2 * Self.sideInset) / widest
        pitch = rowPitch
        var frames: [Frame] = []
        for (r, row) in layout.rows.enumerated() {
            var x = origin.x + Self.sideInset + (widest - Layout.width(row)) / 2 * unit
            let y = origin.y + Self.topInset + CGFloat(r) * rowPitch
            for key in row {
                let hit = CGRect(x: x, y: y, width: key.width * unit, height: rowPitch)
                x += hit.width
                guard key.kind != .gap else { continue }
                let cap = CGRect(x: hit.minX + Self.capGap / 2, y: y + Self.capTop,
                                 width: hit.width - Self.capGap, height: rowPitch - Self.capShortfall)
                frames.append(Frame(key: key, hit: hit, cap: cap, inNumberRow: layout.hasNumberRow && r == 0))
            }
        }
        self.frames = frames
        self.origin = origin
        rowOffset = layout.hasNumberRow ? 1 : 0
    }

    /// SPEC 5.2: every point maps to a key; outside all hit frames, the nearest one wins.
    public func key(at p: CGPoint) -> Frame? {
        frames.min { distanceSquared($0.hit, p) < distanceSquared($1.hit, p) }
    }

    /// The point in key units, the space `Layout.keyCenters()` uses (SPEC 5.2 tap recording): the same
    /// at every height, and the number row (if any) sits above row 0, at y below 0.
    public func keyUnits(_ p: CGPoint) -> Point {
        Point(x: Double((p.x - origin.x - Self.sideInset) / unit),
              y: Double((p.y - origin.y - Self.topInset) / pitch - rowOffset))
    }

    private func distanceSquared(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}
