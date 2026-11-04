import Foundation
import KalamEngine

/// kalam-cli eval-personal --chat <_chat.txt>... [--sender <name>]... [--klex-en <path>] [--klex-ar <path>] [--fold k] [--samples N] [--autocorrect off|gentle|normal] [--set name=value]...
/// Trains a temp personal store on 90% of the senders' messages (sorted by time, then text; message
/// i is held out when i % 10 == fold)
/// and reports next-word top-3, keystroke savings and the autocorrect change rate (each held-out
/// word typed at key centers, then committed) on the rest, base-only vs personal (SPEC 12).
/// --samples prints up to N of the changes (typed -> corrected) per setup.
func evalPersonal(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    guard let chats = flags["chat"], let config = parseConfig(flags), let settings = parseSettings(flags), let fold = Int(flags["fold"]?.last ?? "0"), (0..<10).contains(fold) else {
        print("usage: kalam-cli eval-personal --chat <_chat.txt>... [--sender <name>]... [--klex-en <path>] [--klex-ar <path>] [--fold k] [--samples N] [--autocorrect off|gentle|normal] [--set name=value]...")
        return 2
    }
    guard var messages = readChats(chats) else { return 1 }
    let senders = Set(flags["sender"] ?? messages.map(\.sender))
    // Sorted, so the split doesn't depend on the order of the --chat files.
    messages = messages.filter { senders.contains($0.sender) }
        .sorted { ($0.date ?? .distantPast, $0.text) < ($1.date ?? .distantPast, $1.text) }
    let test = messages.enumerated().filter { $0.offset % 10 == fold }.map(\.element)
    let train = messages.enumerated().filter { $0.offset % 10 != fold }.map(\.element)
    let now = messages.compactMap(\.date).max() ?? Date()  // decay as of the chat's end, not today

    let lexicons = [Lang.en, .ar].compactMap { lang in flags["klex-\(lang.rawValue)"]?.last.flatMap { BaseLexicon(url: URL(fileURLWithPath: $0)) } }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kalam-eval-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let model: PersonalModel
    do {
        model = try trainedModel(train, in: dir, lexicons: lexicons, config: config, now: now)
    } catch {
        print("training failed: \(error)")
        return 1
    }

    print("eval-personal: \(messages.count) messages from \(senders.sorted().joined(separator: ", ")); train \(train.count), test \(test.count)")
    let sampleCount = Int(flags["samples"]?.last ?? "") ?? 0
    print("lang  words  setup       next-word top-3  keystroke savings  autocorrect changes")
    for lang in [Lang.en, .ar] {
        let lexicon = lexicons.first { $0.lang == lang }
        let layout = Layout.bundled("\(lang.rawValue)-letters")
        let words = test.flatMap { contextualWords($0.text) }.filter { $0.token.kind == (lang == .en ? .en : .ar) }
        for (name, personal) in [("base-only", nil), ("personal", model)] {
            let engine = Engine(lang: lang, lexicon: lexicon, layout: layout, personal: personal, config: config)
            let tap = centerTapper(lang)
            let typed = words.map { simulateTyping($0.token, taps: tap($0.token.surface), context: $0.context, engine: engine) }
            let changes = words.compactMap { word -> String? in
                let result = committed(tap(word.token.surface), context: word.context, engine: engine, settings: settings).word
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
    return 0
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
