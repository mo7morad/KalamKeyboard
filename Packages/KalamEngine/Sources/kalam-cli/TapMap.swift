import Foundation
import KalamEngine

/// kalam-cli tapmap --lang en|ar (--personal <db> | --trace <kalam-trace.log>) [--set name=value]...
/// The letters page as rows of keys, each with its sample count and mean tap offset from the key
/// center (SPEC 8.2), in key units and in points on a 402 pt wide keyboard. --personal reads the
/// learned means from a store and adds the effective (shrunk, capped) offset the spatial model uses.
/// --trace reads a device trace's "touch ended" lines; their offsets are to the key the touch ended
/// on, so the hit test biases them, but the mean dy is the value to try as tapOffsetY.
func tapmap(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    let usage = "usage: kalam-cli tapmap --lang en|ar (--personal <db> | --trace <kalam-trace.log>) [--set name=value]..."
    guard let lang = flags["lang"]?.last.flatMap(Lang.init(rawValue:)), let config = parseConfig(flags),
          (flags["personal"] == nil) != (flags["trace"] == nil), let layout = Layout.bundled("\(lang.rawValue)-letters") else {
        print(usage)
        return 2
    }
    var stats: [String: KeyOffset]
    var effective: KeyOffsets?
    if let db = flags["personal"]?.last {
        guard FileManager.default.fileExists(atPath: db), let store = try? PersonalStore(url: URL(fileURLWithPath: db), config: config),
              let learned = try? store.keyOffsets(lang: lang.rawValue) else {
            print("cannot read key offsets from \(db)")
            return 1
        }
        stats = learned
        effective = KeyOffsets(learned, config: config)
    } else {
        let path = flags["trace"]!.last!
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("cannot read \(path)")
            return 1
        }
        stats = traceOffsets(text, layout: layout)
    }

    let xPoints = Double(KeyGeometry(layout: layout, width: 402).unit), yPoints = Double(KeyGeometry.rowPitch)
    func offset(_ x: Double, _ y: Double) -> String {
        String(format: "%+.2f %+.2f (%+5.1f %+5.1f pt)", x, y, x * xPoints, y * yPoints)
    }
    print("tapmap \(lang.rawValue) from \(flags["personal"]?.last ?? flags["trace"]!.last!)")
    print(String(format: "dx dy in key units (x: %.1f pt, y: %.0f pt); negative = left of / above the key center", xPoints, yPoints))
    for (r, row) in layout.rows.enumerated() {
        let keys = row.filter { $0.kind == .char }
        guard !keys.isEmpty else { continue }
        print("row \(r + 1)")
        for key in keys {
            let s = stats[key.output] ?? KeyOffset()
            var line = "  " + key.output.padding(toLength: 3, withPad: " ", startingAt: 0) + String(format: "n %4d  ", s.n)
            line += s.n > 0 ? "mean " + offset(s.dx, s.dy) : "no taps".padding(toLength: 31, withPad: " ", startingAt: 0)
            if let p = effective?.offset(key.output) { line += "  effective " + offset(p.x, p.y) }
            print(line)
        }
    }
    let n = stats.values.reduce(0) { $0 + $1.n }
    let dx = stats.values.reduce(0) { $0 + Double($1.n) * $1.dx } / Double(max(n, 1))
    let dy = stats.values.reduce(0) { $0 + Double($1.n) * $1.dy } / Double(max(n, 1))
    print("all keys  n \(n)  mean " + offset(dx, dy))
    if let effective { print("all keys, shrunk toward the fixed offset: " + offset(effective.global.x, effective.global.y)) }
    if n > 0 { print(String(format: "tapOffsetY to try: %.2f (now %.2f)", dy, config.tapOffsetY)) }
    return 0
}
