import Foundation
import KalamEngine

/// kalam-cli suggest --klex <path> [--lang en|ar] [--context <text>] --typed <letters> [--next <word>] [--top N]
///                   [--chat <_chat.txt>... [--sender <name>]...] [--autocorrect off|gentle|normal] [--set name=value]...
/// Typed letters become taps at their key centers; letters with no key on the page are point-less taps.
/// --chat imports the senders' messages into a temp personal store first, as the host app does.
/// The last line is what a space would commit, then (--next <word>) what it is once the next word commits.
func suggest(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    guard let path = flags["klex"]?.last, let typed = flags["typed"]?.last,
          let lang = Lang(rawValue: flags["lang"]?.last ?? "en"), let config = parseConfig(flags), let settings = parseSettings(flags) else {
        print("usage: kalam-cli suggest --klex <path> [--lang en|ar] [--context <text>] --typed <letters> [--top N] "
              + "[--next <word>] [--chat <_chat.txt>... [--sender <name>]...] [--autocorrect off|gentle|normal] [--set name=value]...")
        return 2
    }
    let lexicon = BaseLexicon(url: URL(fileURLWithPath: path))
    if lexicon == nil { print("warning: \(path) is not a valid .klex, literal only") }
    let layout = Layout.bundled("\(lang.rawValue)-letters")
    let centers = layout?.keyCenters() ?? [:]
    var personal: PersonalModel?
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kalam-suggest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    if let chats = flags["chat"] {
        guard var messages = readChats(chats) else { return 1 }
        if let senders = flags["sender"].map(Set.init) { messages = messages.filter { senders.contains($0.sender) } }
        let now = messages.compactMap(\.date).max() ?? Date()
        do {
            personal = try trainedModel(messages, in: dir, lexicons: lexicon.map { [$0] } ?? [], config: config, now: now)
        } catch {
            print("training failed: \(error)")
            return 1
        }
    }
    let engine = Engine(lang: lang, lexicon: lexicon, layout: layout, personal: personal, config: config)

    let context = contextIdents(flags["context"]?.last ?? "")
    let taps = typed.map { Tap(String($0), at: centers[String($0).lowercased()]) }
    let results = engine.suggest(InputState(context: context, taps: taps), limit: Int(flags["top"]?.last ?? "") ?? 5)

    print("context: \(context.joined(separator: " "))  typed: \(typed)")
    print(" #  candidate         score      lm  spatial   edits   compl   boost")
    for (rank, s) in results.enumerated() {
        let name = s.isLiteral ? "\"\(s.text)\"" : s.text
        let numbers = [s.score, s.lm, s.spatial, s.edits, s.completion, s.boosts].map { String(format: "%7.2f", $0) }
        print(String(format: "%2d  ", rank + 1) + name.padding(toLength: 14, withPad: " ", startingAt: 0) + " " + numbers.joined(separator: " "))
    }
    print("space commits: \(committed(taps, context: context, engine: engine, settings: settings).word)")
    if let next = flags["next"]?.last {
        print("after \(next): \(committed(taps, context: context, next: next, engine: engine, settings: settings).word)")
    }
    return 0
}
