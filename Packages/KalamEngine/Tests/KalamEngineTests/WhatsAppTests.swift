import Foundation
import Testing
@testable import KalamEngine

private let calendar = Calendar(identifier: .gregorian)
private let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

private func parsedFixture(_ name: String) throws -> [ChatMessage] {
    parseWhatsApp(try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8), now: now, calendar: calendar)
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0) -> Date? {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))
}

@Test func parsesTheIOSExport() throws {
    let messages = try parsedFixture("whatsapp-ios.txt")
    #expect(messages.map(\.text) == [
        "see you tomorrow", "ok habibi", "first line\nsecond line of the same message", "month first with pm",
        "four digit year no seconds", "fixed wording", "انا عايز اروح", "future date",
    ])
    #expect(Set(messages.map(\.sender)) == ["Moe", "Sara Test 💙"])
    #expect(messages.map(\.date) == [
        date(2024, 3, 1, 9, 15, 30), date(2024, 3, 1, 9, 16), date(2024, 3, 13, 20, 53, 1), date(2024, 3, 14, 21, 5, 12),
        date(2024, 3, 15, 7, 0), date(2024, 3, 16, 10, 1), date(2024, 3, 16, 10, 2), nil,
    ])
}

@Test func parsesTheAndroidExport() throws {
    let messages = try parsedFixture("whatsapp-android.txt")
    #expect(messages.map(\.text) == ["hello there", "twelve hour", "lowercase am", "multi\nline", "month first", "ok 3ashan kda"])
    #expect(messages.map(\.sender) == ["Moe", "Sara", "Moe", "Moe", "Moe", "Moe"])
    #expect(messages.map(\.date) == [
        date(2024, 3, 1, 9, 16), date(2024, 3, 1, 21, 17), date(2024, 3, 1, 9, 18), date(2024, 3, 1, 9, 22),
        date(2024, 2, 14, 10, 0), date(2024, 3, 1, 9, 24),
    ])
}

@Test func importedWordsSeenTwiceBecomeKnown() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    let lexicon = try #require(BaseLexicon(data: fixtureData(.en)))
    try store.importTexts([("yalla bina", nil), ("yalla", nil)], lexicons: [lexicon], now: now)  // dialect, not in base
    #expect(try store.word(lang: "en", ident: "yalla")?.state == .known)
    #expect(try store.word(lang: "en", ident: "bina")?.state == .pending)
    let undated = now.timeIntervalSince1970 - EngineConfig().undatedImportAgeDays * 86_400
    #expect(try store.word(lang: "en", ident: "bina")?.hits.time == undated)
}

@Test(arguments: [
    (Lang.en, "dont"),  // shares its key with the valid don't
    (Lang.en, "alot"),  // an invalid base variant
    (Lang.ar, "انا"),  // shares its key with the valid أنا
])
func importNeverMakesALazySpellingKnown(_ lang: Lang, _ word: String) throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    let lexicon = try #require(BaseLexicon(data: fixtureData(lang)))
    try store.importTexts(Array(repeating: (word, nil), count: 5), lexicons: [lexicon], now: now)
    let row = try #require(try store.word(lang: lang.rawValue, ident: word))
    #expect(row.state == .pending && row.hits.count == 5)
}

@Test(arguments: [(Lang.en, "dont", "don't" as String?), (Lang.ar, "انا", nil)])
func importedLazySpellingFollowsTheDefaultVariantFix(_ lang: Lang, _ typed: String, _ expected: String?) throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    let lexicon = try #require(BaseLexicon(data: fixtureData(lang)))
    try store.importTexts(Array(repeating: (typed, nil), count: 5), lexicons: [lexicon], now: now)
    let engine = Engine(lang: lang, lexicon: lexicon, layout: Layout.bundled("\(lang.rawValue)-letters"),
                        personal: PersonalModel(store: store, clock: { now }))
    let input = InputState(context: [], taps: typed.map { Tap(String($0)) })
    #expect(engine.autocorrection(input, ranked: engine.candidates(input), traits: FieldTraits(), settings: Settings())?.ident == expected)
}

@Test func rareNeighbourOfAFrequentWordIsALikelyTypo() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    let texts = Array(repeating: "tamam", count: 20) + ["tamma", "tamma", "ya basha", "ya basha"]
    try store.importTexts(texts.map { ($0, nil) }, lexicons: [], now: now)
    #expect(try store.word(lang: "en", ident: "tamma")?.state == .pending)
    #expect(try store.corrections().contains(LearningBatch.CorrectionKey(lang: "en", typed: "tamma", chosen: "tamam", rejected: false)))
    #expect(try store.word(lang: "en", ident: "basha")?.state == .known)  // no frequent neighbour
}

@Test func validBaseWordIsNeverALikelyTypo() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    let lexicon = try #require(BaseLexicon(data: fixtureData(.en)))
    let texts = Array(repeating: "hello", count: 20) + ["hell", "hell"]
    try store.importTexts(texts.map { ($0, nil) }, lexicons: [lexicon], now: now)
    #expect(try store.word(lang: "en", ident: "hell")?.state == .known)
}

@Test func importedTypoIsAutocorrectedNotProtected() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    let lexicon = try #require(BaseLexicon(data: fixtureData(.en)))
    try store.importTexts((Array(repeating: "tamam", count: 20) + ["tamma", "tamma"]).map { ($0, nil) }, lexicons: [lexicon], now: now)
    let engine = Engine(lang: .en, lexicon: lexicon, layout: Layout.bundled("en-letters"),
                        personal: PersonalModel(store: store, clock: { now }))
    let input = InputState(context: [], taps: taps("tamma"))
    let ranked = engine.candidates(input)
    #expect(engine.autocorrection(input, ranked: ranked, traits: FieldTraits(), settings: Settings())?.ident == "tamam")
}
