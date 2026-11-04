import CoreGraphics

/// Key frames in points for one page at a given width, from Apple's iPhone 17 metrics
/// (docs/reference/README.md), tuned so the rendered caps land on Apple's pixels. Hit frames tile
/// each row with no gaps; caps are the drawn keys.
public struct KeyGeometry: Sendable {
    public struct Frame: Sendable {
        public let key: Layout.Key
        public let hit: CGRect
        public let cap: CGRect
    }

    /// Hit area inset from the left and right edges.
    static let sideInset: CGFloat = 3.4
    /// Space between neighbouring caps.
    static let capGap: CGFloat = 6
    /// Key area top to the first hit row.
    static let topInset: CGFloat = 7
    public static let rowPitch: CGFloat = 54
    static let capTop: CGFloat = 1.1
    static let capHeight: CGFloat = 42.8
    /// Height of the key area, excluding the suggestion bar. Apple's is 226; a third-party keyboard
    /// gets a 17 pt taller globe strip below it on iOS 27, so we keep only 3.5 pt under the bottom row.
    public static let height: CGFloat = topInset + 3 * rowPitch + capTop + capHeight + 3.5

    public let frames: [Frame]
    /// Points per key unit, horizontally.
    public let unit: CGFloat
    private let origin: CGPoint

    /// `origin` is the top-left of the key area in the caller's coordinates. Gap keys get no frame.
    public init(layout: Layout, width: CGFloat, origin: CGPoint = .zero) {
        let widest = layout.widestRow
        unit = (width - 2 * Self.sideInset) / widest
        var frames: [Frame] = []
        for (r, row) in layout.rows.enumerated() {
            var x = origin.x + Self.sideInset + (widest - Layout.width(row)) / 2 * unit
            let y = origin.y + Self.topInset + CGFloat(r) * Self.rowPitch
            for key in row {
                let hit = CGRect(x: x, y: y, width: key.width * unit, height: Self.rowPitch)
                x += hit.width
                guard key.kind != .gap else { continue }
                let cap = CGRect(x: hit.minX + Self.capGap / 2, y: y + Self.capTop,
                                 width: hit.width - Self.capGap, height: Self.capHeight)
                frames.append(Frame(key: key, hit: hit, cap: cap))
            }
        }
        self.frames = frames
        self.origin = origin
    }

    /// SPEC 5.2: every point maps to a key; outside all hit frames, the nearest one wins.
    public func key(at p: CGPoint) -> Frame? {
        frames.min { distanceSquared($0.hit, p) < distanceSquared($1.hit, p) }
    }

    /// The point in key units, the space `Layout.keyCenters()` uses (SPEC 5.2 tap recording).
    public func keyUnits(_ p: CGPoint) -> Point {
        Point(x: Double((p.x - origin.x - Self.sideInset) / unit),
              y: Double((p.y - origin.y - Self.topInset) / Self.rowPitch))
    }

    private func distanceSquared(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}
