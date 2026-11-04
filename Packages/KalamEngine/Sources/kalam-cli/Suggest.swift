import Foundation
import KalamEngine

/// kalam-cli suggest --klex <path> [--lang en|ar] [--context <text>] --typed <letters> [--top N] [--set name=value]...
/// Typed letters become taps at their key centers; letters with no key on the page are point-less taps.
func suggest(_ args: [String]) -> Int32 {
    let flags = parseFlags(args)
    guard let path = flags["klex"]?.last, let typed = flags["typed"]?.last,
          let lang = Lang(rawValue: flags["lang"]?.last ?? "en"), let config = parseConfig(flags) else {
        print("usage: kalam-cli suggest --klex <path> [--lang en|ar] [--context <text>] --typed <letters> [--top N] [--set name=value]...")
        return 2
    }
    let lexicon = BaseLexicon(url: URL(fileURLWithPath: path))
    if lexicon == nil { print("warning: \(path) is not a valid .klex, literal only") }
    let layout = Layout.bundled("\(lang.rawValue)-letters")
    let centers = layout?.keyCenters() ?? [:]
    let engine = Engine(lang: lang, lexicon: lexicon, layout: layout, config: config)

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
    return 0
}
