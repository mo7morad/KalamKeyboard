/// Key centers by normalized char, from one layout page. One normalized char can sit on several
/// keys (AR: ي and ى, ه and ة); a tap is measured against the nearest.
struct SpatialModel {
    private var centers: [UInt16: [Point]] = [:]

    init(layout: Layout?) {
        guard let layout else { return }
        for (output, center) in layout.keyCenters() {
            let units = Array(normalize(output, lang: layout.lang).utf16)
            if units.count == 1 { centers[units[0], default: []].append(center) }
        }
    }

    /// Squared distance from the point to the nearest key for this char; nil when no key has it.
    func distanceSquared(_ unit: UInt16, _ point: Point) -> Double? {
        centers[unit]?.map { ($0.x - point.x) * ($0.x - point.x) + ($0.y - point.y) * ($0.y - point.y) }.min()
    }
}
