import CryptoKit
import Foundation
import KalamEngine

/// kalam-cli eval --lang en|ar --klex <file> --heldout <file> [--personal <db>] [--limit N] [--seed S] [--set name=value]...
/// Types `limit` seeded-random held-out sentences with Gaussian tap noise on the letters page and
/// reports the SPEC 12 metrics plus request latency on this machine.
func eval(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    guard let lang = flags["lang"]?.last.flatMap(Lang.init(rawValue:)), let klex = flags["klex"]?.last,
          let heldout = flags["heldout"]?.last, let config = parseConfig(flags),
          let limit = Int(flags["limit"]?.last ?? "500"), let seed = UInt64(flags["seed"]?.last ?? "1") else {
        print("usage: kalam-cli eval --lang en|ar --klex <file> --heldout <file> [--personal <db>] [--limit N] [--seed S] [--set name=value]...")
        return 2
    }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: klex), options: .alwaysMapped), let lexicon = BaseLexicon(data: data),
          let text = try? String(contentsOfFile: heldout, encoding: .utf8), let layout = Layout.bundled("\(lang.rawValue)-letters") else {
        print("cannot read \(klex) or \(heldout)")
        return 1
    }
    var personal: PersonalModel?
    if let db = flags["personal"]?.last {
        guard let store = try? PersonalStore(url: URL(fileURLWithPath: db), config: config) else {
            print("cannot open \(db)")
            return 1
        }
        personal = PersonalModel(store: store, config: config)
    }
    let engine = Engine(lang: lang, lexicon: lexicon, layout: layout, personal: personal, config: config)
    var rng = SplitMix64(state: seed)
    let sentences = text.split(separator: "\n").map(String.init).shuffled(using: &rng).prefix(limit)
    let noisy = NoisyTypist(layout: layout, sigma: 0.35)
    let clean = centerTapper(lang)
    let latency = Latencies()
    var metrics = Metrics()
    let started = Date()

    for sentence in sentences {
        for (token, context) in contextualWords(sentence) where token.kind == (lang == .en ? .en : .ar) {
            let taps = noisy.taps(token.surface, using: &rng)  // drawn up front: the same noise whatever the engine does
            let typed = simulateTyping(token, taps: taps, context: context, engine: engine, latency: latency)
            metrics.words += 1
            metrics.predicted += typed.predicted ? 1 : 0
            metrics.keystrokes += typed.keystrokes
            metrics.baseline += typed.baseline
            guard let word = lexicon.wordID(ident: token.ident), lexicon.isValid(word) else { continue }
            if ident(taps.map(\.char).joined(), kind: token.kind) != token.ident {
                metrics.noisy += 1
                let result = committed(taps, context: context, engine: engine, latency: latency)
                metrics.fixed += result.word == token.ident ? 1 : 0
                metrics.rankedFirst += result.top == token.ident ? 1 : 0
            }
            metrics.clean += 1
            metrics.falseFixes += committed(clean(token.surface), context: context, engine: engine).word == token.ident ? 0 : 1
        }
    }

    print("eval \(lang.rawValue): \(sentences.count) sentences, \(metrics.words) words, seed \(seed), \(String(format: "%.0f", Date().timeIntervalSince(started))) s")
    print("klex sha256 \(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())")
    print("params: \((flags["set"] ?? []).isEmpty ? "defaults" : (flags["set"] ?? []).joined(separator: " "))")
    metrics.report(latency)
    return 0
}

private struct Metrics {
    var words = 0, predicted = 0, keystrokes = 0, baseline = 0
    var noisy = 0, fixed = 0, rankedFirst = 0, clean = 0, falseFixes = 0

    func rate(_ part: Int, _ whole: Int) -> Double { 100 * Double(part) / Double(max(whole, 1)) }

    func report(_ latency: Latencies) {
        print(String(format: "autocorrect top-1 on noisy words   %5.1f%%  (%d of %d known words came out mistyped)", rate(fixed, noisy), noisy, clean))
        print(String(format: "  (noisy target ranked first        %5.1f%%)", rate(rankedFirst, noisy)))
        print(String(format: "false autocorrect on clean words   %5.2f%%  (%d of %d; guard <= 0.5%%)", rate(falseFixes, clean), falseFixes, clean))
        print(String(format: "next-word top-3                    %5.1f%%", rate(predicted, words)))
        print(String(format: "keystroke savings                  %5.1f%%", 100 - rate(keystrokes, baseline)))
        print("latency candidates p50/p95/p99     \(Latencies.summary(latency.candidates))  (\(latency.candidates.count) requests)")
        print("latency predict    p50/p95/p99     \(Latencies.summary(latency.predict))  (\(latency.predict.count) requests)")
    }
}

/// Taps with Gaussian noise around the key centers of a letters page. A tap types the char key whose
/// hit rect is nearest to the noisy point (rects tile the rows, as in KeyGeometry); a tap that lands
/// on a non-char key (shift, backspace, a gap) goes to the nearest char key instead.
/// Chars with no key on the page (EN apostrophe, AR long-press alternates) are point-less exact taps.
private struct NoisyTypist {
    private let centers: [String: Point]
    private let halfWidths: [String: Double]
    let sigma: Double

    init(layout: Layout, sigma: Double) {
        centers = layout.keyCenters()
        halfWidths = Dictionary(layout.rows.joined().filter { $0.kind == .char }.map { ($0.output, $0.width / 2) }) { a, _ in a }
        self.sigma = sigma
    }

    func taps(_ word: String, using rng: inout SplitMix64) -> [Tap] {
        word.map { letter in
            guard let center = centers[letter.lowercased()] else { return Tap(String(letter), at: nil) }
            let point = Point(x: center.x + sigma * rng.gaussian(), y: center.y + sigma * rng.gaussian())
            let hit = key(at: point)
            return Tap(letter.isUppercase ? hit.uppercased() : hit, at: point)
        }
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

    /// Standard normal (Box-Muller).
    mutating func gaussian() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &self), u2 = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
