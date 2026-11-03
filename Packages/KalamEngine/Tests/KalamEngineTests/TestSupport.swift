import Foundation
import Testing
@testable import KalamEngine

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardized

func fixtureData(_ lang: Lang) throws -> Data {
    try Data(contentsOf: fixtures.appendingPathComponent("fixture-\(lang.rawValue).klex"))
}

func fixtureEngine(_ lang: Lang) throws -> Engine {
    let lexicon = try #require(BaseLexicon(url: fixtures.appendingPathComponent("fixture-\(lang.rawValue).klex")))
    return Engine(lang: lang, lexicon: lexicon, layout: Layout.bundled("\(lang.rawValue)-letters"))
}

/// Taps at the key centers of en-letters; chars with no key are point-less.
func taps(_ typed: String) -> [Tap] {
    let centers = Layout.bundled("en-letters")?.keyCenters() ?? [:]
    return typed.map { Tap(String($0), at: centers[String($0)]) }
}

func suggestions(_ engine: Engine, _ typed: String, context: [String] = [], limit: Int = 3) -> [String] {
    engine.suggest(InputState(context: context, taps: taps(typed)), limit: limit).map(\.text)
}
