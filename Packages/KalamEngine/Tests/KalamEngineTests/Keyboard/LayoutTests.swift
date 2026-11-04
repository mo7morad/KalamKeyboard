import Testing
@testable import KalamEngine

@Test func englishLettersCentersInKeyUnits() throws {
    let layout = try #require(Layout.bundled("en-letters"))
    let centers = layout.keyCenters()
    #expect(centers.count == 26)
    #expect(centers["q"] == Point(x: 0.5, y: 0.5))
    #expect(centers["p"] == Point(x: 9.5, y: 0.5))
    #expect(centers["a"] == Point(x: 1.0, y: 1.5))  // 9-key row is centered
    #expect(centers["z"] == Point(x: 2.0, y: 2.5))  // after a 1.5-wide shift
}

@Test func keyDefaultsApply() throws {
    let keys = try #require(Layout.bundled("en-letters")).rows.joined()
    let q = try #require(keys.first { $0.id == "q" })
    #expect((q.output, q.width, q.kind, q.popup) == ("q", 1, .char, true))
    let space = try #require(keys.first { $0.kind == .space })
    #expect((space.output, space.popup) == (" ", false))
}

let pageIDs = ["en-letters", "en-numbers", "en-symbols", "ar-letters", "ar-numbers", "ar-symbols"]

@Test(arguments: pageIDs)
func everyPageLoadsWithUniqueIDsAndFullRows(_ id: String) throws {
    let layout = try #require(Layout.bundled(id))
    let ids = layout.rows.joined().map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(layout.rows.count == 4)
    // Every row but EN letters row 2 (indented half a key each side) spans the full width.
    let short = layout.rows.filter { abs(Layout.width($0) - layout.widestRow) > 0.001 }
    #expect(short.count == (id == "en-letters" ? 1 : 0))
}

@Test func letterPagesCarryAppleAndSpecAlternates() throws {
    let en = try #require(Layout.bundled("en-letters")).rows.joined()
    let ar = try #require(Layout.bundled("ar-letters")).rows.joined()
    func alternates(_ keys: some Sequence<Layout.Key>, _ id: String) -> [String] { keys.first { $0.id == id }?.alternates ?? [] }
    #expect(alternates(en, "e") == ["ë", "é", "e", "è", "ê", "ě", "ẽ", "ē", "ė", "ę"])
    #expect(alternates(en, "c") == ["c", "ç", "ć", "č", "ċ"])
    #expect(alternates(en, "o") == ["ő", "ō", "õ", "ø", "œ", "ǒ", "ö", "ó", "ò", "o", "ô"])  // Phase 5 recapture
    #expect(alternates(en, "l") == ["ľ", "ļ", "ł", "l"])
    // SPEC 5.1 minimums for Arabic.
    #expect(Set(["أ", "إ", "آ", "ء"]).isSubset(of: alternates(ar, "ا")))
    #expect(Set(["ى", "ئ"]).isSubset(of: alternates(ar, "ي")))
    #expect(alternates(ar, "و").contains("ؤ"))
    #expect(alternates(ar, "ه").contains("ة"))
}

@Test func topRowsHintDigitsLeftToRight() throws {
    let en = try #require(Layout.bundled("en-letters")).rows[0]
    let ar = try #require(Layout.bundled("ar-letters")).rows[0]
    #expect(en.compactMap(\.hint).joined() == "1234567890")
    #expect(ar.compactMap(\.hint).joined() == "1234567890")
    #expect(ar.first?.hint == "1" && ar.last?.hint == nil)  // ض..ح, then ج without a digit
}

@Test func globeKeyTakesItsRoomFromSpace() throws {
    let layout = try #require(Layout.bundled("ar-letters"))
    let bottom = layout.withGlobeKey().rows[3]
    #expect(bottom.map(\.kind) == [.page, .globe, .lang, .space, .char, .return])
    #expect(abs(Layout.width(bottom) - layout.widestRow) < 0.001)
    #expect(layout.withGlobeKey().rows[0].count == layout.rows[0].count)
}

@Test func arabicDigitsFollowTheSetting() throws {
    let numbers = try #require(Layout.bundled("ar-numbers"))
    #expect(numbers.withDigits(eastern: false).rows[0].map(\.output).joined() == "1234567890")
    let letters = try #require(Layout.bundled("ar-letters"))
    #expect(letters.withDigits(eastern: true).rows[0].compactMap(\.hint).joined() == "١٢٣٤٥٦٧٨٩٠")
}

@Test func numberRowAddsDigitsAndDropsTheTopRowHints() throws {
    let en = try #require(Layout.bundled("en-letters")).withNumberRow(digits: "1234567890".map(String.init))
    #expect(en.hasNumberRow && en.rows.count == 5)
    #expect(en.rows[0].map(\.output).joined() == "1234567890")
    #expect(en.rows[0].allSatisfy { $0.kind == .char && $0.popup && $0.alternates.isEmpty })
    #expect(en.rows[1].allSatisfy { $0.hint == nil })
    let e = try #require(en.rows[1].first { $0.id == "e" })
    #expect(e.alternates.contains("é"))  // the letter's own strip stays
    let q = try #require(en.rows[1].first)
    #expect(longPressStrip(output: q.output, hint: q.hint, alternates: q.alternates, hintShown: false) == nil)
}

@Test(arguments: [false, true])
func arabicNumberRowSpansTheRowAndFollowsTheDigitSetting(_ eastern: Bool) throws {
    let digits = try #require(Layout.bundled("ar-numbers")?.rows.first).map(\.output)
    let ar = try #require(Layout.bundled("ar-letters")).withNumberRow(digits: digits).withDigits(eastern: eastern)
    #expect(ar.rows[0].map(\.output).joined() == (eastern ? "١٢٣٤٥٦٧٨٩٠" : "1234567890"))
    #expect(abs(Layout.width(ar.rows[0]) - ar.widestRow) < 0.001)
    #expect(ar.widestRow == 11)
    #expect(ar.withGlobeKey().hasNumberRow)
    let ids = ar.rows.joined().map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test(arguments: ["en-letters", "ar-letters"])
func numberRowKeepsThePagesKeyCenters(_ id: String) throws {
    let layout = try #require(Layout.bundled(id))
    #expect(layout.withNumberRow(digits: ["1", "2", "3"]).keyCenters() == layout.keyCenters())
}
