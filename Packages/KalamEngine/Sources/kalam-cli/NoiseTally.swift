import Foundation

/// What eval-personal --noise got for one held-out word that its noisy taps mistyped.
struct NoisyResult {
    let literal: String  // what the noisy taps typed
    let kinds: Set<TypoKind>
    let realWord: Bool  // the literal is itself a word (Engine.isWord): rule 2 never corrects it
    let word: String  // committed
    let top: String?  // ranked first
}

/// eval-personal --noise counts for one language (SPEC 12), summed over folds.
struct NoiseTally {
    var words = 0, wrongChanges = 0  // clean taps of every counted word
    var noisy = 0, fixed = 0, rankedFirst = 0, realWord = 0, realWordFixed = 0
    var misses: [String: Int] = [:]  // by bucket
    var samples: [String] = []
    let sampleLimit: Int

    init(sampleLimit: Int = 0) { self.sampleLimit = sampleLimit }

    /// One counted word: `noisy` is nil when the noisy taps typed it right; `clean` is what its key-centre taps committed.
    mutating func add(_ target: String, noisy result: NoisyResult?, clean: String) {
        words += 1
        if clean != target {
            wrongChanges += 1
            sample("wrong  \(target) -> \(clean)")
        }
        guard let result else { return }
        noisy += 1
        realWord += result.realWord ? 1 : 0
        rankedFirst += result.top == target ? 1 : 0
        if result.word == target {
            fixed += 1
            realWordFixed += result.realWord ? 1 : 0
            return
        }
        let bucket = Self.bucket(result.kinds, realWord: result.realWord)
        misses[bucket, default: 0] += 1
        let kinds = result.realWord ? "real-word: \(Self.bucket(result.kinds, realWord: false))" : bucket
        sample("miss   [\(kinds)] \(target): typed \(result.literal) -> \(result.word) (top \(result.top ?? "none"))")
    }

    /// A miss's bucket: real-word, else its error kinds joined ("omission+swap").
    static func bucket(_ kinds: Set<TypoKind>, realWord: Bool) -> String {
        realWord ? "real-word" : TypoKind.allCases.filter(kinds.contains).map(\.rawValue).joined(separator: "+")
    }

    static func + (a: NoiseTally, b: NoiseTally) -> NoiseTally {
        var sum = a
        sum.words += b.words
        sum.wrongChanges += b.wrongChanges
        sum.noisy += b.noisy
        sum.fixed += b.fixed
        sum.rankedFirst += b.rankedFirst
        sum.realWord += b.realWord
        sum.realWordFixed += b.realWordFixed
        sum.misses.merge(b.misses, uniquingKeysWith: +)
        sum.samples = Array((a.samples + b.samples).prefix(a.sampleLimit))
        return sum
    }

    func report(_ lang: String) -> [String] {
        func rate(_ part: Int, _ whole: Int) -> String { String(format: "%5.1f%%", 100 * Double(part) / Double(max(whole, 1))) }
        let buckets = misses.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        return ["\(lang): \(words) words, \(noisy) came out mistyped",
                "  fix rate     \(rate(fixed, noisy))  (\(fixed) of \(noisy))",
                "  top-1 rate   \(rate(rankedFirst, noisy))",
                "  wrong change \(rate(wrongChanges, words))  (\(wrongChanges) of \(words) clean words)",
                "  real-word    \(realWord) of the mistyped, \(realWordFixed) fixed",
                "  misses (\(noisy - fixed)): " + buckets.map { "\($0.key) \($0.value)" }.joined(separator: ", ")]
            + samples.map { "    \($0)" }
    }

    private mutating func sample(_ line: String) {
        if samples.count < sampleLimit { samples.append(line) }
    }
}
