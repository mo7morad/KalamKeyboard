import Foundation
import Testing
@testable import KalamEngine

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func state(_ store: PersonalStore, _ ident: String, lang: String = "en") throws -> WordRow.State? {
    try store.word(lang: lang, ident: ident)?.state
}

@Test func chatImportLearnsOnlyTheChosenSenders() throws {
    let messages = parseWhatsApp(try String(contentsOf: fixtures.appendingPathComponent("whatsapp-ios.txt"), encoding: .utf8), now: now)
    #expect(senderCounts(messages).map(\.sender) == ["Moe", "Sara Test 💙"])
    let store = try PersonalStore(url: temporaryStoreURL())
    try store.importChat(messages, senders: ["Moe"], lexicons: [], now: now)
    #expect(try store.word(lang: "en", ident: "tomorrow") != nil)
    #expect(try store.word(lang: "ar", ident: "عايز") != nil)
    #expect(try store.word(lang: "en", ident: "habibi") == nil)  // Sara's
}

@Test func statsCountWordsPerLangAndState() throws {
    let store = try personalStore(["yalla yalla bina", "yalla", "يلا يلا"])
    try store.block(lang: "en", ident: "bina", display: "bina", now: 0)
    let stats = try store.stats()
    #expect(stats.words["en"] == StoreStats.Words(known: 1, pending: 0, blocked: 1))
    #expect(stats.words["ar"] == StoreStats.Words(known: 1, pending: 0, blocked: 0))
    #expect(stats.ngrams > 0)
}

@Test func learnedWordsAreSearchedByNormalizedFormMostFrequentFirst() throws {
    let store = try personalStore(["أنا", "انت انت", "hello"])
    #expect(try store.learnedWords(lang: "ar").map(\.ident) == ["انت", "أنا"])
    #expect(try store.learnedWords(lang: "ar", search: "انا").map(\.ident) == ["أنا"])
    #expect(try store.learnedWords(lang: "en", search: "HEL").map(\.display) == ["hello"])
}

@Test func forgetDeletesTheWordWithItsNgrams() throws {
    let store = try personalStore(["see you tomorrow", "see you tomorrow"])
    try store.forget(lang: "en", ident: "you")
    #expect(try store.word(lang: "en", ident: "you") == nil)
    #expect(try store.continuations(lang: "en", w1: "", w2: "see").isEmpty)
    #expect(try store.continuations(lang: "en", w1: "", w2: "you").isEmpty)
    #expect(try store.word(lang: "en", ident: "tomorrow")?.state == .known)
}

@Test func blockedWordIsUnblockedByAddingItManually() throws {
    let store = try personalStore(["kda kda"])
    let word = try #require(try store.learnedWords(lang: "en").first)
    try store.block(word)
    #expect(try state(store, "kda") == .blocked)
    #expect(try store.addManually("kda Omar") == 2)
    #expect(try [state(store, "kda"), state(store, "omar")] == [.known, .known])
}

@Test func resetLearningEmptiesTheStore() throws {
    let store = try personalStore(["see you tomorrow"])
    try store.resetLearning()
    #expect(try store.stats() == StoreStats())
}

@Test func backupRestoresIntoAStoreAnotherConnectionHoldsOpen() throws {
    let url = temporaryStoreURL()
    let store = try PersonalStore(url: url)
    try store.addManually("habibi")
    let backup = url.deletingLastPathComponent().appendingPathComponent("backup.sqlite")
    try store.backup(to: backup)
    let keyboard = try PersonalStore(url: url)
    try store.resetLearning()
    try store.addManually("other")

    try store.restore(from: backup)
    #expect(try keyboard.word(lang: "en", ident: "habibi")?.state == .known)
    #expect(try keyboard.word(lang: "en", ident: "other") == nil)
    var mode = ""
    try SQLite(url: url).query("PRAGMA journal_mode") { mode = $0.text(0) }
    #expect(mode == "wal")
}

@Test func restoreRejectsAFileThatIsNotAKalamStoreAndKeepsTheData() throws {
    let store = try personalStore(["kda kda"])
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kalam-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let text = dir.appendingPathComponent("chat.txt"), otherDB = dir.appendingPathComponent("other.sqlite")
    try Data("not a database".utf8).write(to: text)
    try SQLite(url: otherDB).execute("CREATE TABLE notes(body TEXT); PRAGMA user_version = 1")

    for file in [text, otherDB] {
        #expect(throws: StoreError.notAKalamStore) { try store.restore(from: file) }
    }
    #expect(try state(store, "kda") == .known)
}
