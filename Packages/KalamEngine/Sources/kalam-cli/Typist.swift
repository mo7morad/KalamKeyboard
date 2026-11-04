import KalamEngine

/// One word typed by the simulated typist.
struct TypedWord {
    let keystrokes: Int  // taps used, the final suggestion tap or space included
    let baseline: Int  // letters + space, with no suggestions
    let predicted: Bool  // in the top slots before the first letter (next-word top-N)
}

/// The simulated typist (SPEC 12): it taps the target as soon as it shows in the top `slots`
/// suggestions (predictions before the first letter; one tap includes the space), else types the
/// next letter through `tap`, which places it (key center, or with noise for eval).
func simulateTyping(_ word: Token, context: [String], engine: Engine, slots: Int = 3, tap: (Character) -> Tap) -> TypedWord {
    let letters = Array(word.surface)
    let baseline = letters.count + 1
    if engine.predict(context: context, limit: slots).contains(where: { $0.ident == word.ident }) {
        return TypedWord(keystrokes: 1, baseline: baseline, predicted: true)
    }
    var taps: [Tap] = []
    for (i, letter) in letters.enumerated().dropLast() {
        taps.append(tap(letter))
        if engine.suggest(InputState(context: context, taps: taps), limit: slots).contains(where: { $0.ident == word.ident }) {
            return TypedWord(keystrokes: i + 2, baseline: baseline, predicted: false)
        }
    }
    return TypedWord(keystrokes: baseline, baseline: baseline, predicted: false)
}

/// Taps at the key centers of a language's letters page; chars with no key are point-less.
func centerTapper(_ lang: Lang) -> (Character) -> Tap {
    let centers = Layout.bundled("\(lang.rawValue)-letters")?.keyCenters() ?? [:]
    return { Tap(String($0), at: centers[String($0).lowercased()]) }
}
