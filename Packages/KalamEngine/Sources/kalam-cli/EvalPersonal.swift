import Foundation
import KalamEngine

/// kalam-cli eval-personal --chat <_chat.txt>... [--sender <name>]... [--klex-en <path>] [--klex-ar <path>] [--fold k] [--samples N] [--autocorrect off|gentle|normal] [--set name=value]...
///                         [--noise <sigma> [--fold all] [--bias-x X] [--bias-y Y] [--seed S] [--count-klex-en|--count-klex-ar <path>]]
/// Trains a temp personal store on 90% of the senders' messages (sorted by time, then text; message
/// i is held out when i % 10 == fold)
/// and reports next-word top-3, keystroke savings and the autocorrect change rate (each held-out
/// word typed at key centers, then committed) on the rest, base-only vs personal (SPEC 12).
/// --samples prints up to N of the changes (typed -> corrected) per setup.
/// --noise reports the autocorrect fix rate instead (evalNoise); --fold all sums the 10 folds.
/// --count-klex-<lang> also requires each counted word to be a word with that lexicon (one word set for two lexicons).
func evalPersonal(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    let noiseFlag = flags["noise"]?.last, sigma = noiseFlag.flatMap(Double.init)
    let foldFlag = flags["fold"]?.last ?? "0"
    guard let chats = flags["chat"], let config = parseConfig(flags), let settings = parseSettings(flags), (noiseFlag == nil) == (sigma == nil),
          let folds = foldFlag == "all" && sigma != nil ? Array(0..<10) : Int(foldFlag).map({ [$0] }), folds.allSatisfy((0..<10).contains),
          let biasX = Double(flags["bias-x"]?.last ?? "0"), let biasY = Double(flags["bias-y"]?.last ?? "-0.13"),
          let seed = UInt64(flags["seed"]?.last ?? "1") else {
        print("usage: kalam-cli eval-personal --chat <_chat.txt>... [--sender <name>]... [--klex-en <path>] [--klex-ar <path>] [--fold k] [--samples N] "
              + "[--autocorrect off|gentle|normal] [--set name=value]... [--noise <sigma> [--fold all] [--bias-x X] [--bias-y Y] [--seed S] [--count-klex-en|--count-klex-ar <path>]]")
        return 2
    }
    guard var messages = readChats(chats) else { return 1 }
    let senders = Set(flags["sender"] ?? messages.map(\.sender))
    // Sorted, so the split doesn't depend on the order of the --chat files.
    messages = messages.filter { senders.contains($0.sender) }
        .sorted { ($0.date ?? .distantPast, $0.text) < ($1.date ?? .distantPast, $1.text) }
    let lexicons = [Lang.en, .ar].compactMap { lang in flags["klex-\(lang.rawValue)"]?.last.flatMap { BaseLexicon(url: URL(fileURLWithPath: $0)) } }
    // --count-klex-<lang>: count only the words that are words with this lexicon too (compare two lexicons on one word set).
    let countLexicons = [Lang.en, .ar].compactMap { lang in flags["count-klex-\(lang.rawValue)"]?.last.flatMap { BaseLexicon(url: URL(fileURLWithPath: $0)) } }
    let sampleCount = Int(flags["samples"]?.last ?? "") ?? 0
    print("eval-personal: \(messages.count) messages from \(senders.sorted().joined(separator: ", ")); folds \(folds.map(String.init).joined(separator: ","))")

    if let sigma {
        print("noise: sigma \(sigma), tap bias \(biasX),\(biasY), seed \(seed), params \((flags["set"] ?? []).isEmpty ? "defaults" : (flags["set"] ?? []).joined(separator: " "))")
        var tallies = [Lang.en: NoiseTally(sampleLimit: sampleCount), .ar: NoiseTally(sampleLimit: sampleCount)]
        for fold in folds {
            let (train, test) = split(messages, fold: fold)
            var rng = SplitMix64(state: seed &+ UInt64(fold))
            let ok = withTrainedModel(train, all: messages, lexicons: lexicons, config: config) { model in
                for lang in [Lang.en, .ar] {
                    let engine = Engine(lang: lang, lexicon: lexicons.first { $0.lang == lang }, layout: Layout.bundled("\(lang.rawValue)-letters"), personal: model, config: config)
                    let typist = NoisyTypist(layout: Layout.bundled("\(lang.rawValue)-letters")!, sigma: sigma, bias: Point(x: biasX, y: biasY))
                    let countEngine = countLexicons.first { $0.lang == lang }.map { Engine(lang: lang, lexicon: $0, layout: nil, personal: model, config: config) }
                    tallies[lang] = tallies[lang]! + evalNoise(test, engine: engine, typist: typist, settings: settings, rng: &rng, sampleLimit: sampleCount,
                                                               counted: { engine.isWord($0) && countEngine?.isWord($0) != false })
                }
            }
            guard ok else { return 1 }
        }
        [Lang.en, .ar].forEach { tallies[$0]!.report($0.rawValue).forEach { print($0) } }
        return 0
    }

    let (train, test) = split(messages, fold: folds[0])
    print("train \(train.count), test \(test.count)")
    print("lang  words  setup       next-word top-3  keystroke savings  autocorrect changes")
    let ok = withTrainedModel(train, all: messages, lexicons: lexicons, config: config) { model in
        for lang in [Lang.en, .ar] {
            let lexicon = lexicons.first { $0.lang == lang }
            let layout = Layout.bundled("\(lang.rawValue)-letters")
            let words = test.flatMap { wordsWithNext($0.text) }.filter { $0.token.kind == (lang == .en ? .en : .ar) }
            for (name, personal) in [("base-only", nil), ("personal", model)] {
                let engine = Engine(lang: lang, lexicon: lexicon, layout: layout, personal: personal, config: config)
                let tap = centerTapper(lang)
                let typed = words.map { simulateTyping($0.token, taps: tap($0.token.surface), context: $0.context, engine: engine) }
                let changes = words.compactMap { word -> String? in
                    let result = committed(tap(word.token.surface), context: word.context, next: word.next, engine: engine, settings: settings).word
                    return result == word.token.ident ? nil : "\(word.token.surface) -> \(result)"
                }
                let top3 = Double(typed.filter(\.predicted).count) / Double(max(typed.count, 1))
                let savings = 1 - Double(typed.reduce(0) { $0 + $1.keystrokes }) / Double(max(typed.reduce(0) { $0 + $1.baseline }, 1))
                print(lang.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0) + String(format: "%5d  ", words.count)
                      + name.padding(toLength: 12, withPad: " ", startingAt: 0)
                      + String(format: "%14.1f%%  %16.1f%%  %18.1f%%", top3 * 100, savings * 100, 100 * Double(changes.count) / Double(max(words.count, 1))))
                changes.prefix(sampleCount).forEach { print("    \($0)") }
            }
        }
    }
    return ok ? 0 : 1
}

/// eval-personal --noise for one fold and language: each held-out word that is a word to the engine
/// (Engine.isWord, with the personal model trained on the rest) is typed twice: with the typist's
/// noise (drawn up front, so the same whatever the engine does), and at key centres.
func evalNoise(_ test: [ChatMessage], engine: Engine, typist: NoisyTypist, settings: Settings, rng: inout SplitMix64, sampleLimit: Int,
               counted: (String) -> Bool) -> NoiseTally {
    var tally = NoiseTally(sampleLimit: sampleLimit)
    let kind: Token.Kind = engine.lang == .en ? .en : .ar
    let clean = centerTapper(engine.lang)
    for (token, context, next) in test.flatMap({ wordsWithNext($0.text) }) where token.kind == kind && counted(token.ident) {
        let (taps, kinds) = typist.taps(token.surface, using: &rng)
        let literal = ident(taps.map(\.char).joined(), kind: kind)
        let noisy = literal == token.ident ? nil : committed(taps, context: context, next: next, engine: engine, settings: settings)
        tally.add(token.ident, noisy: noisy.map { NoisyResult(literal: literal, kinds: kinds, realWord: engine.isWord(literal), word: $0.word, top: $0.top) },
                  clean: committed(clean(token.surface), context: context, next: next, engine: engine, settings: settings).word)
    }
    return tally
}

/// Message i is held out when i % 10 == fold.
private func split(_ messages: [ChatMessage], fold: Int) -> (train: [ChatMessage], test: [ChatMessage]) {
    (messages.enumerated().filter { $0.offset % 10 != fold }.map(\.element), messages.enumerated().filter { $0.offset % 10 == fold }.map(\.element))
}

/// Runs `body` with a personal model trained on `train` in a temp store, decayed as of the chats' end
/// (not today); false (after printing why) when training fails.
private func withTrainedModel(_ train: [ChatMessage], all: [ChatMessage], lexicons: [BaseLexicon], config: EngineConfig,
                              _ body: (PersonalModel) -> Void) -> Bool {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kalam-eval-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    do {
        body(try trainedModel(train, in: dir, lexicons: lexicons, config: config, now: all.compactMap(\.date).max() ?? Date()))
        return true
    } catch {
        print("training failed: \(error)")
        return false
    }
}

func readChats(_ paths: [String]) -> [ChatMessage]? {
    var messages: [ChatMessage] = []
    for path in paths {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("cannot read \(path)")
            return nil
        }
        messages += parseWhatsApp(text)
    }
    return messages
}

func trainedModel(_ train: [ChatMessage], in dir: URL, lexicons: [BaseLexicon], config: EngineConfig, now: Date) throws -> PersonalModel {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try PersonalStore(url: dir.appendingPathComponent("personal.sqlite"), config: config)
    try store.importTexts(train.map { ($0.text, $0.date) }, lexicons: lexicons, now: now)
    return PersonalModel(store: store, config: config, clock: { now })
}
