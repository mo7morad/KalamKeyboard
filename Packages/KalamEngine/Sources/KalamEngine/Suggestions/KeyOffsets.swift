import Foundation

/// A running mean of where Moe's taps land relative to one key's center, in key units (SPEC 8.2).
public struct KeyOffset: Equatable, Sendable {
    public var n = 0
    public var dx = 0.0
    public var dy = 0.0

    public init(n: Int = 0, dx: Double = 0, dy: Double = 0) {
        (self.n, self.dx, self.dy) = (n, dx, dy)
    }

    /// Adds one sample. n stops at maxSamples, so each later sample keeps a weight of 1 / maxSamples
    /// and the mean follows a drift in Moe's typing.
    mutating func add(_ sample: Point, maxSamples: Int) {
        n = min(n + 1, max(maxSamples, 1))
        dx += (sample.x - dx) / Double(n)
        dy += (sample.y - dy) / Double(n)
    }
}

/// The offset the spatial model applies to each key (SPEC 8.2): a key's mean shrunk toward the
/// all-keys mean of its language, which is itself shrunk toward the fixed tap offset, so keys with
/// little data follow the others. Capped at keyOffsetCap so a key's center always maps to that key.
public struct KeyOffsets: Sendable {
    public let stats: [String: KeyOffset]  // by key output
    /// The all-keys mean, shrunk toward the fixed offset.
    public let global: Point
    private let prior: Double
    private let cap: Double

    public init(_ stats: [String: KeyOffset], config: EngineConfig) {
        self.stats = stats
        prior = max(config.keyOffsetPrior, 0)
        cap = config.keyOffsetCap
        let total = Double(stats.values.reduce(0) { $0 + $1.n })
        let sumX = stats.values.reduce(0) { $0 + Double($1.n) * $1.dx }, sumY = stats.values.reduce(0) { $0 + Double($1.n) * $1.dy }
        let weight = total + prior
        global = weight > 0
            ? Point(x: (sumX + prior * config.tapOffsetX) / weight, y: (sumY + prior * config.tapOffsetY) / weight)
            : Point(x: config.tapOffsetX, y: config.tapOffsetY)
    }

    /// The effective offset of a key: (n * mean + K * global) / (n + K), at most `cap` long.
    public func offset(_ key: String) -> Point {
        let s = stats[key] ?? KeyOffset()
        let n = Double(s.n), weight = n + prior
        var p = weight > 0 ? Point(x: (n * s.dx + prior * global.x) / weight, y: (n * s.dy + prior * global.y) / weight) : global
        let length = (p.x * p.x + p.y * p.y).squareRoot()
        if length > cap { p = Point(x: p.x * cap / length, y: p.y * cap / length) }
        return p
    }
}

/// SPEC 9.2: the (key, tap - key center) samples of a committed word on its letters page. Only when
/// the taps with points pair one to one, in order, with the letters of the word's normalized form;
/// a pair whose tap is more than 1 key unit from its letter's key (an edit) is skipped. A letter on
/// several keys (AR ي and ى) is measured to the nearest.
func offsetSamples(_ word: String, taps: [Tap], layout: Layout) -> [(key: String, offset: Point)] {
    let letters = Array(normalize(word, lang: layout.lang).utf16)
    let points = taps.compactMap(\.point)
    guard !letters.isEmpty, points.count == letters.count else { return [] }
    var keys: [UInt16: [(output: String, center: Point)]] = [:]
    for (output, center) in layout.keyCenters() {
        let units = Array(normalize(output, lang: layout.lang).utf16)
        if units.count == 1 { keys[units[0], default: []].append((output, center)) }
    }
    func length2(_ p: Point) -> Double { p.x * p.x + p.y * p.y }
    var samples: [(key: String, offset: Point)] = []
    for (unit, p) in zip(letters, points) {
        let offsets = (keys[unit] ?? []).map { (key: $0.output, offset: Point(x: p.x - $0.center.x, y: p.y - $0.center.y)) }
        guard let nearest = offsets.min(by: { length2($0.offset) < length2($1.offset) }), length2(nearest.offset) <= 1 else { continue }
        samples.append(nearest)
    }
    return samples
}

/// For `kalam-cli tapmap --trace`: the offset of every "touch ended <key id> at x,y" line of a
/// keyboard trace (KeyboardExtension/Debug/Trace.swift) to the center of the letters-page key it
/// ended on, by key output. Lines for keys not on the page (other pages, space) are skipped.
public func traceOffsets(_ trace: String, layout: Layout, maxSamples: Int = .max) -> [String: KeyOffset] {
    let outputs = Dictionary(layout.rows.joined().filter { $0.kind == .char }.map { ($0.id, $0.output) }) { a, _ in a }
    let centers = layout.keyCenters()
    var stats: [String: KeyOffset] = [:]
    for line in trace.split(separator: "\n") {
        guard let range = line.range(of: " touch ended ") else { continue }
        let fields = line[range.upperBound...].split(separator: " ")
        guard fields.count >= 3, fields[1] == "at", let output = outputs[String(fields[0])], let center = centers[output] else { continue }
        let xy = fields[2].split(separator: ",").compactMap { Double($0) }
        guard xy.count == 2, xy[0] >= 0 || xy[1] >= 0 else { continue }  // -1,-1: no geometry
        stats[output, default: KeyOffset()].add(Point(x: xy[0] - center.x, y: xy[1] - center.y), maxSamples: maxSamples)
    }
    return stats
}

/// A (typed char, intended char) pair of normalized UTF-16 units, as one value.
func confusionPair(_ typed: UInt16, _ intended: UInt16) -> UInt32 { UInt32(typed) << 16 | UInt32(intended) }

/// SPEC 8.2 learned confusion pairs: from the non-rejected corrections whose typed and chosen words
/// have the same normalized length and differ in exactly one position, the (typed, intended) char
/// pairs seen in at least minCorrections distinct corrections, by store lang.
func confusionPairs(_ corrections: Set<LearningBatch.CorrectionKey>, minCorrections: Int) -> [String: Set<UInt32>] {
    var counts: [String: [UInt32: Int]] = [:]
    for c in corrections where !c.rejected {
        guard let lang = Lang(rawValue: c.lang) else { continue }
        let typed = Array(normalize(c.typed, lang: lang).utf16), chosen = Array(normalize(c.chosen, lang: lang).utf16)
        guard typed.count == chosen.count else { continue }
        let differing = typed.indices.filter { typed[$0] != chosen[$0] }
        guard differing.count == 1, let i = differing.first else { continue }
        counts[c.lang, default: [:]][confusionPair(typed[i], chosen[i]), default: 0] += 1
    }
    return counts.mapValues { Set($0.filter { $0.value >= minCorrections }.keys) }
}
