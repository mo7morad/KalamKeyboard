import Foundation
import KalamEngine

/// kalam-cli eval-personal --chat <_chat.txt>... [--sender <name>]... [--klex-en <path>] [--klex-ar <path>] [--set name=value]...
/// Trains a temp personal store on 90% of the senders' messages (every 10th message is held out)
/// and reports next-word top-3 and keystroke savings on the rest, base-only vs personal (SPEC 12).
func evalPersonal(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    guard let chats = flags["chat"], let config = parseConfig(flags) else {
        print("usage: kalam-cli eval-personal --chat <_chat.txt>... [--sender <name>]... [--klex-en <path>] [--klex-ar <path>] [--set name=value]...")
        return 2
    }
    guard var messages = readChats(chats) else { return 1 }
    let senders = Set(flags["sender"] ?? messages.map(\.sender))
    messages = messages.filter { senders.contains($0.sender) }
    let test = messages.enumerated().filter { $0.offset % 10 == 9 }.map(\.element)
    let train = messages.enumerated().filter { $0.offset % 10 != 9 }.map(\.element)
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
    print("lang  words  setup       next-word top-3  keystroke savings")
    for lang in [Lang.en, .ar] {
        let lexicon = lexicons.first { $0.lang == lang }
        let layout = Layout.bundled("\(lang.rawValue)-letters")
        let words = test.flatMap { contextualWords($0.text) }.filter { $0.token.kind == (lang == .en ? .en : .ar) }
        for (name, personal) in [("base-only", nil), ("personal", model)] {
            let engine = Engine(lang: lang, lexicon: lexicon, layout: layout, personal: personal, config: config)
            let typed = words.map { simulateTyping($0.token, context: $0.context, engine: engine, tap: centerTapper(lang)) }
            let top3 = Double(typed.filter(\.predicted).count) / Double(max(typed.count, 1))
            let savings = 1 - Double(typed.reduce(0) { $0 + $1.keystrokes }) / Double(max(typed.reduce(0) { $0 + $1.baseline }, 1))
            print(lang.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0) + String(format: "%5d  ", words.count)
                  + name.padding(toLength: 12, withPad: " ", startingAt: 0) + String(format: "%14.1f%%  %16.1f%%", top3 * 100, savings * 100))
        }
    }
    return 0
}

private func readChats(_ paths: [String]) -> [ChatMessage]? {
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

private func trainedModel(_ train: [ChatMessage], in dir: URL, lexicons: [BaseLexicon], config: EngineConfig, now: Date) throws -> PersonalModel {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try PersonalStore(url: dir.appendingPathComponent("personal.sqlite"), config: config)
    try store.importTexts(train.map { ($0.text, $0.date) }, lexicons: lexicons, now: now)
    return PersonalModel(store: store, config: config, clock: { now })
}
