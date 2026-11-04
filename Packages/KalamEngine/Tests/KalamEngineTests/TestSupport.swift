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

/// Taps at the key centers of a letters page; chars with no key are point-less.
func taps(_ typed: String, on page: String = "en-letters") -> [Tap] {
    let centers = Layout.bundled(page)?.keyCenters() ?? [:]
    return typed.map { Tap(String($0), at: centers[String($0)]) }
}

func suggestions(_ engine: Engine, _ typed: String, context: [String] = [], limit: Int = 3) -> [String] {
    engine.suggest(InputState(context: context, taps: taps(typed)), limit: limit).map(\.text)
}

/// A fresh store path in its own temp directory.
func temporaryStoreURL() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kalam-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("personal.sqlite")
}

/// A store holding the texts as imports at time 0 (words seen twice become known), and its model.
func personalStore(_ texts: [String], edit: (inout LearningBatch) -> Void = { _ in }) throws -> PersonalStore {
    let store = try PersonalStore(url: temporaryStoreURL())
    var batch = LearningBatch(halfLife: EngineConfig().halfLife)
    for text in texts { batch.addText(text, at: 0, source: .import) }
    edit(&batch)
    try store.write(batch)
    return store
}

let epoch = { Date(timeIntervalSince1970: 0) }

func personalEngine(_ lang: Lang, _ texts: [String], edit: (inout LearningBatch) -> Void = { _ in }) throws -> Engine {
    let model = PersonalModel(store: try personalStore(texts, edit: edit), clock: epoch)
    let lexicon = try #require(BaseLexicon(url: fixtures.appendingPathComponent("fixture-\(lang.rawValue).klex")))
    return Engine(lang: lang, lexicon: lexicon, layout: Layout.bundled("\(lang.rawValue)-letters"), personal: model)
}
