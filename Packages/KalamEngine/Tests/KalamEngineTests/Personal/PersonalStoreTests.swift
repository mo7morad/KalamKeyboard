import Foundation
import Testing
@testable import KalamEngine

private let day = 86_400.0
private let halfLife = EngineConfig().halfLife

private func typed(_ word: String, session: Int, at time: Double = 0, explicit: Bool = false) -> LearningBatch {
    var batch = LearningBatch(halfLife: halfLife)
    batch.addWord(word, kind: .en, context: [], at: time, source: .typed, session: session, explicit: explicit)
    return batch
}

private func state(_ store: PersonalStore, _ ident: String, lang: String = "en") throws -> WordRow.State? {
    try store.word(lang: lang, ident: ident)?.state
}

@Test func hitsHalveEveryHalfLife() {
    var hits = Hits()
    hits.add(1, at: 0, halfLife: halfLife)
    #expect(abs(hits.value(at: 60 * day, halfLife: halfLife) - 0.5) < 1e-12)
    hits.add(1, at: 60 * day, halfLife: halfLife)
    #expect(abs(hits.count - 1.5) < 1e-12 && hits.time == 60 * day)
    hits.add(1, at: 0, halfLife: halfLife)  // an older hit (import) merges at the later time
    #expect(abs(hits.count - 2.0) < 1e-12 && hits.time == 60 * day)
}

@Test func freshStoreIsMigratedAndReopens() throws {
    let url = temporaryStoreURL()
    try PersonalStore(url: url).write(typed("hello", session: 1))
    let db = try SQLite(url: url)
    var (version, mode) = (0, "")
    try db.query("PRAGMA user_version") { version = $0.int(0) }
    try db.query("PRAGMA journal_mode") { mode = $0.text(0) }
    #expect(version == PersonalStore.schemaVersion && mode == "wal")
    #expect(try PersonalStore(url: url).word(lang: "en", ident: "hello")?.hits.count == 1)
}

@Test func newerSchemaIsRejected() throws {
    let url = temporaryStoreURL()
    try SQLite(url: url).execute("PRAGMA user_version = 99")
    #expect(throws: SQLiteError.self) { try PersonalStore(url: url) }
}

@Test func twoTypedUsesInOneSessionStayPending() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    try store.write(typed("kda", session: 1))
    try store.write(typed("kda", session: 1))
    #expect(try state(store, "kda") == .pending)
    try store.write(typed("kda", session: 2, at: 30 * day))
    #expect(try state(store, "kda") == .known)
}

@Test(arguments: [WordSource.manual, .lexicon])
func manualAndLexiconWordsAreKnownAtOnce(_ source: WordSource) throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    var batch = LearningBatch(halfLife: halfLife)
    batch.addWord("Omar", kind: .en, context: [], at: 0, source: source)
    try store.write(batch)
    #expect(try state(store, "omar") == .known)
}

@Test func explicitAcceptMakesAWordKnownAtOnce() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    try store.write(typed("yalla", session: 1, explicit: true))
    #expect(try state(store, "yalla") == .known)
}

@Test func secondImportMakesAWordKnown() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    var batch = LearningBatch(halfLife: halfLife)
    batch.addText("3ashan kda", at: 0, source: .import)
    batch.addText("3ashan", at: 0, source: .import)
    try store.write(batch)
    #expect(try [state(store, "3ashan"), state(store, "kda")] == [.known, .pending])
}

@Test func blockedWordStaysBlockedUntilAddedManually() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    try store.write(typed("teh", session: 1, explicit: true))
    try store.block(lang: "en", ident: "teh", display: "teh", now: 0)
    try store.write(typed("teh", session: 2, explicit: true))
    #expect(try state(store, "teh") == .blocked)
    var manual = LearningBatch(halfLife: halfLife)
    manual.addWord("teh", kind: .en, context: [], at: 0, source: .manual)
    try store.write(manual)
    #expect(try state(store, "teh") == .known)
}

@Test func displayIsTheMajorityFormIgnoringSentenceStarts() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    var batch = LearningBatch(halfLife: halfLife)
    for _ in 0..<3 { batch.addWord("Hello", kind: .en, context: [sentenceStart], at: 0, source: .typed) }
    batch.addWord("iPhone", kind: .en, context: ["my"], at: 0, source: .typed)
    batch.addWord("iphone", kind: .en, context: ["an"], at: 0, source: .typed)
    batch.addWord("iPhone", kind: .en, context: ["the"], at: 0, source: .typed)
    batch.addWord("hello", kind: .en, context: ["say"], at: 0, source: .typed)
    try store.write(batch)
    #expect(try store.word(lang: "en", ident: "iphone")?.display == "iPhone")
    #expect(try store.word(lang: "en", ident: "hello")?.display == "hello")
}

@Test func ngramsKeepTheirContextAndAccumulateAcrossWrites() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    for _ in 0..<2 {
        var batch = LearningBatch(halfLife: halfLife)
        batch.addText("see you tomorrow", at: 0, source: .import)
        try store.write(batch)
    }
    #expect(try store.continuations(lang: "en", w1: "", w2: "you")["tomorrow"]?.count == 2)
    #expect(try store.continuations(lang: "en", w1: "see", w2: "you")["tomorrow"]?.count == 2)
    #expect(try store.continuations(lang: "en", w1: "", w2: sentenceStart).keys.sorted() == ["see"])
}

@Test func writersInTwoConnectionsBothLand() throws {
    let url = temporaryStoreURL()
    let keyboard = try PersonalStore(url: url), app = try PersonalStore(url: url)
    for i in 0..<10 { try (i.isMultiple(of: 2) ? keyboard : app).write(typed("hi", session: i)) }
    #expect(try keyboard.word(lang: "en", ident: "hi")?.hits.count == 10)
}

@Test func writeWaitsForTheBusyTimeoutThenFailsWithoutPartialData() throws {
    let url = temporaryStoreURL()
    let store = try PersonalStore(url: url)
    let other = try SQLite(url: url)
    try other.execute("BEGIN IMMEDIATE")
    let start = Date()
    #expect(throws: SQLiteError.self) { try store.write(typed("hi", session: 1)) }
    #expect(Date().timeIntervalSince(start) >= 0.15)
    try other.execute("COMMIT")
    #expect(try store.word(lang: "en", ident: "hi") == nil)
}

@Test func aVersion1StoreGainsTheKeyOffsetsTable() throws {
    let url = temporaryStoreURL()
    try PersonalStore(url: url).write(typed("hello", session: 1))
    try SQLite(url: url).execute("DROP TABLE key_offsets; PRAGMA user_version = 1")
    let store = try PersonalStore(url: url)
    var batch = LearningBatch(halfLife: halfLife)
    batch.keyOffsets[LearningBatch.KeyOffsetKey(lang: "en", key: "q")] = [Point(x: 0.1, y: -0.1)]
    try store.write(batch)
    #expect(try store.keyOffsets(lang: "en")["q"] == KeyOffset(n: 1, dx: 0.1, dy: -0.1))
    #expect(try store.word(lang: "en", ident: "hello")?.hits.count == 1)
}

@Test func keyOffsetsKeepARunningMeanWithCappedN() throws {
    var config = EngineConfig()
    config.keyOffsetMaxSamples = 4
    let store = try PersonalStore(url: temporaryStoreURL(), config: config)
    let key = LearningBatch.KeyOffsetKey(lang: "en", key: "q")
    for samples in [[0.0, 0.0], [0.0, 0.0], [1.0]] {
        var batch = LearningBatch(halfLife: halfLife)
        batch.keyOffsets[key] = samples.map { Point(x: $0, y: -$0) }
        try store.write(batch)
    }
    let q = try #require(try store.keyOffsets(lang: "en")["q"])
    #expect(q.n == 4 && abs(q.dx - 0.25) < 1e-9 && abs(q.dy + 0.25) < 1e-9)
    try store.resetLearning()
    #expect(try store.keyOffsets(lang: "en").isEmpty)
}
