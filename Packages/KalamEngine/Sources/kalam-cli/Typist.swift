import Foundation
import KalamEngine

/// One word typed by the simulated typist.
struct TypedWord {
    let keystrokes: Int  // taps used, the final suggestion tap or space included
    let baseline: Int  // letters + space, with no suggestions
    let predicted: Bool  // in the top slots before the first letter (next-word top-N)
}

/// The simulated typist (SPEC 12): it taps the target as soon as it shows in the top `slots`
/// suggestions (predictions before the first letter; one tap includes the space), else types the
/// next of `taps`, one per letter of the word (key centers, or with noise for eval).
func simulateTyping(_ word: Token, taps: [Tap], context: [String], engine: Engine, slots: Int = 3,
                    latency: Latencies = Latencies()) -> TypedWord {
    let baseline = taps.count + 1
    if latency.time(\.predict, { engine.predict(context: context, limit: slots) }).contains(where: { $0.ident == word.ident }) {
        return TypedWord(keystrokes: 1, baseline: baseline, predicted: true)
    }
    for i in taps.indices.dropLast() {
        let shown = latency.time(\.candidates) { engine.suggest(InputState(context: context, taps: Array(taps[...i])), limit: slots) }
        if shown.contains(where: { $0.ident == word.ident }) {
            return TypedWord(keystrokes: i + 2, baseline: baseline, predicted: false)
        }
    }
    return TypedWord(keystrokes: baseline, baseline: baseline, predicted: false)
}

/// Taps at the key centers of a language's letters page; chars with no key are point-less.
func centerTapper(_ lang: Lang) -> (String) -> [Tap] {
    let centers = Layout.bundled("\(lang.rawValue)-letters")?.keyCenters() ?? [:]
    return { word in word.map { Tap(String($0), at: centers[String($0).lowercased()]) } }
}

/// What Moe ends up with when he commits these taps with a space (the autocorrect, else the
/// literal), and the top-ranked candidate.
func committed(_ taps: [Tap], context: [String], engine: Engine, latency: Latencies = Latencies()) -> (word: String, top: String?) {
    let input = InputState(context: context, taps: taps)
    let ranked = latency.time(\.candidates) { engine.candidates(input) }
    let fix = engine.autocorrection(input, ranked: ranked, traits: FieldTraits(), settings: Settings())
    return (fix?.ident ?? ident(input.literal, kind: engine.lang == .en ? .en : .ar), ranked.first?.ident)
}

/// Request wall times in ms.
final class Latencies {
    var candidates: [Double] = []
    var predict: [Double] = []

    func time<T>(_ samples: ReferenceWritableKeyPath<Latencies, [Double]>, _ work: () -> T) -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        self[keyPath: samples].append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        return result
    }

    /// "p50 / p95 / p99" of the samples.
    static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return "n/a" }
        return [0.5, 0.95, 0.99].map { String(format: "%.2f", sorted[min(Int(Double(sorted.count) * $0), sorted.count - 1)]) }
            .joined(separator: " / ") + " ms"
    }
}
