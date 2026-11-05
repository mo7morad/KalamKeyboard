import CryptoKit
import Foundation
import KalamEngine

/// kalam-cli eval --lang en|ar --klex <file> --heldout <file> [--personal <db>] [--limit N] [--seed S] [--autocorrect off|gentle|normal]
///               [--bias-x X] [--bias-y Y] [--set name=value]...
/// Types `limit` seeded-random held-out sentences with tap noise (Gaussian around the key center
/// shifted by the bias in key units, plus omissions, extra taps and swaps; see NoisyTypist) on the
/// letters page and reports the SPEC 12 metrics plus request latency on this machine.
func eval(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    guard let lang = flags["lang"]?.last.flatMap(Lang.init(rawValue:)), let klex = flags["klex"]?.last,
          let heldout = flags["heldout"]?.last, let config = parseConfig(flags), let settings = parseSettings(flags),
          let limit = Int(flags["limit"]?.last ?? "500"), let seed = UInt64(flags["seed"]?.last ?? "1"),
          let biasX = Double(flags["bias-x"]?.last ?? "0"), let biasY = Double(flags["bias-y"]?.last ?? "0") else {
        print("usage: kalam-cli eval --lang en|ar --klex <file> --heldout <file> [--personal <db>] [--limit N] [--seed S] "
              + "[--autocorrect off|gentle|normal] [--bias-x X] [--bias-y Y] [--set name=value]...")
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
    let noisy = NoisyTypist(layout: layout, sigma: 0.35, bias: Point(x: biasX, y: biasY))
    let clean = centerTapper(lang)
    let latency = Latencies()
    var metrics = Metrics()
    let started = Date()

    for sentence in sentences {
        for (token, context) in contextualWords(sentence) where token.kind == (lang == .en ? .en : .ar) {
            let taps = noisy.taps(token.surface, using: &rng).taps  // drawn up front: the same noise whatever the engine does
            let typed = simulateTyping(token, taps: taps, context: context, engine: engine, latency: latency)
            metrics.words += 1
            metrics.predicted += typed.predicted ? 1 : 0
            metrics.keystrokes += typed.keystrokes
            metrics.baseline += typed.baseline
            guard let word = lexicon.wordID(ident: token.ident), lexicon.isValid(word) else { continue }
            if ident(taps.map(\.char).joined(), kind: token.kind) != token.ident {
                metrics.noisy += 1
                let result = committed(taps, context: context, engine: engine, settings: settings, latency: latency)
                metrics.fixed += result.word == token.ident ? 1 : 0
                metrics.rankedFirst += result.top == token.ident ? 1 : 0
            }
            metrics.clean += 1
            metrics.falseFixes += committed(clean(token.surface), context: context, engine: engine, settings: settings).word == token.ident ? 0 : 1
        }
    }

    print("eval \(lang.rawValue): \(sentences.count) sentences, \(metrics.words) words, seed \(seed), \(String(format: "%.0f", Date().timeIntervalSince(started))) s")
    print("klex sha256 \(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())")
    print("params: \((flags["set"] ?? []).isEmpty ? "defaults" : (flags["set"] ?? []).joined(separator: " ")), tap bias \(biasX),\(biasY)")
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
