import Foundation
import KalamEngine

/// Taps with Gaussian noise around the key centers of a letters page, shifted by a systematic bias
/// (Moe's taps land high). The shifted point is what is tapped: a tap types the char key whose
/// hit rect is nearest to the noisy point (rects tile the rows, as in KeyGeometry); a tap that lands
/// on a non-char key (shift, backspace, a gap) goes to the nearest char key instead.
/// On top, per letter: a swap with the next letter, an omission, or an extra tap after it (half a
/// doubled tap, half a neighbouring key). A one-letter word gets no omission.
/// Chars with no key on the page (EN apostrophe, AR long-press alternates) are point-less exact taps, never edited.
/// Each word comes with the kinds of error it got, for eval-personal --noise.
struct NoisyTypist {
    private let centers: [String: Point]
    private let halfWidths: [String: Double]
    private let neighbours: [String: [String]]  // keys whose centers are within 1.2 key units
    let sigma: Double
    let bias: Point
    let omissionRate: Double, extraRate: Double, swapRate: Double

    init(layout: Layout, sigma: Double, bias: Point, omissionRate: Double = 0.015, extraRate: Double = 0.015, swapRate: Double = 0.005) {
        let centers = layout.keyCenters()
        self.centers = centers
        halfWidths = Dictionary(layout.rows.joined().filter { $0.kind == .char }.map { ($0.output, $0.width / 2) }) { a, _ in a }
        neighbours = centers.mapValues { c in
            centers.filter { $0.value != c && hypot($0.value.x - c.x, $0.value.y - c.y) <= 1.2 }.keys.sorted()
        }
        self.sigma = sigma
        self.bias = bias
        (self.omissionRate, self.extraRate, self.swapRate) = (omissionRate, extraRate, swapRate)
    }

    func taps(_ word: String, using rng: inout SplitMix64) -> (taps: [Tap], kinds: Set<TypoKind>) {
        var letters = Array(word)
        var kinds: Set<TypoKind> = []
        var i = 0
        while i + 1 < letters.count {
            let swappable = centers[letters[i].lowercased()] != nil && centers[letters[i + 1].lowercased()] != nil
            if swappable, rng.chance(swapRate) {
                letters.swapAt(i, i + 1)
                kinds.insert(.swap)
                i += 1
            }
            i += 1
        }
        var taps: [Tap] = []
        for letter in letters {
            let output = letter.lowercased()
            guard centers[output] != nil else {
                taps.append(Tap(String(letter), at: nil))
                continue
            }
            if letters.count > 1, rng.chance(omissionRate) {
                kinds.insert(.omission)
                continue
            }
            let hit = tap(output, upper: letter.isUppercase, using: &rng)
            if hit.char.lowercased() != output { kinds.insert(.substitution) }
            taps.append(hit)
            if rng.chance(extraRate) {
                let extra = rng.chance(0.5) ? output : neighbours[output]?.randomElement(using: &rng) ?? output
                taps.append(tap(extra, upper: letter.isUppercase, using: &rng))
                kinds.insert(.extraTap)
            }
        }
        return (taps, kinds)
    }

    private func tap(_ output: String, upper: Bool, using rng: inout SplitMix64) -> Tap {
        let center = centers[output]!
        let point = Point(x: center.x + bias.x + sigma * rng.gaussian(), y: center.y + bias.y + sigma * rng.gaussian())
        let hit = key(at: point)
        return Tap(upper ? hit.uppercased() : hit, at: point)
    }

    private func key(at p: Point) -> String {
        func distance(_ output: String) -> Double {
            let c = centers[output]!, half = halfWidths[output] ?? 0.5
            let dx = max(abs(p.x - c.x) - half, 0), dy = max(abs(p.y - c.y) - 0.5, 0)
            return dx * dx + dy * dy
        }
        return centers.keys.min { (distance($0), $0) < (distance($1), $1) }!
    }
}

/// The kinds of error NoisyTypist makes. A substitution is a tap that typed another key.
enum TypoKind: String, CaseIterable {
    case substitution, omission, extraTap = "extra tap", swap
}

/// Seeded, so a run is reproducible (SplitMix64).
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }

    /// Standard normal (Box-Muller).
    mutating func gaussian() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &self), u2 = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
