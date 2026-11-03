import Foundation
import Testing
@testable import KalamEngine

/// The fixture source the Python writer built the checked-in .klex files from.
private struct FixtureSource: Decodable {
    let words: [String: Double]
    let bigrams: [String: Double]  // "w1 w2" -> P(w2 | w1)
    let casing: [String: String]
}

private func source(_ lang: Lang) throws -> FixtureSource {
    let data = try Data(contentsOf: fixtures.appendingPathComponent("fixture-source.json"))
    return try #require(try JSONDecoder().decode([String: FixtureSource].self, from: data)[lang.rawValue])
}

@Test(arguments: [Lang.en, .ar])
func roundTripsTheFixtureSource(_ lang: Lang) throws {
    let lexicon = try #require(BaseLexicon(data: fixtureData(lang)))
    let src = try source(lang)
    #expect(lexicon.lang == lang)
    #expect(lexicon.verifyChecksum())
    #expect(lexicon.counts.variants == src.words.count)
    for (surface, freq) in src.words {
        let id = try #require(lexicon.wordID(ident: surface), "\(surface)")
        #expect(lexicon.surface(id) == surface)
        #expect(abs(lexicon.logProb(id) - log(freq)) < 0.001, "\(surface)")
        #expect(lexicon.isValid(id) == (log10(freq) + 9 >= 2), "\(surface)")
    }
    for (pair, p) in src.bigrams {
        let words = try pair.split(separator: " ").map { try #require(lexicon.wordID(ident: String($0))) }
        let logProb = try #require(lexicon.bigramLogProb(words[0], words[1]), "\(pair)")
        #expect(abs(logProb - log(p)) < 0.001, "\(pair)")
    }
    for (surface, display) in src.casing {
        #expect(lexicon.casing(try #require(lexicon.wordID(ident: surface))) == display)
    }
}

@Test(arguments: [(Lang.en, "dont", ["don't", "dont"]), (.ar, "انا", ["انا", "أنا"]), (.ar, "علي", ["على", "علي"])])
func variantsShareTheirNormalizedKey(_ lang: Lang, _ key: String, _ surfaces: [String]) throws {
    let lexicon = try #require(BaseLexicon(data: fixtureData(lang)))
    let found = try #require(lexicon.key(for: key))
    #expect(lexicon.variants(ofKey: found).map(lexicon.surface) == surfaces)  // most probable first
}

@Test func arabicPreferredSpellingIsFlagged() throws {
    let lexicon = try #require(BaseLexicon(data: fixtureData(.ar)))
    #expect(lexicon.isPreferred(try #require(lexicon.wordID(ident: "أنا"))))
    #expect(!lexicon.isPreferred(try #require(lexicon.wordID(ident: "انا"))))
}

private func patched(_ data: Data, at offset: Int, _ value: UInt32) -> Data {
    var copy = data
    withUnsafeBytes(of: value.littleEndian) { copy.replaceSubrange(offset..<offset + 4, with: $0) }
    return copy
}

@Test func rejectsBadMagic() throws {
    #expect(BaseLexicon(data: patched(try fixtureData(.en), at: 0, 0x4B4C_4558)) == nil)
}

@Test func rejectsTruncatedFile() throws {
    let data = try fixtureData(.en)
    #expect(BaseLexicon(data: data.prefix(BaseLexicon.headerSize - 1)) == nil)
    #expect(BaseLexicon(data: data.dropLast()) == nil)  // the last section no longer fits
}

@Test(arguments: [12, 16, 20, 84, 88])  // node offset, node length, node count, string offset, string length
func rejectsOutOfRangeSection(_ field: Int) throws {
    #expect(BaseLexicon(data: patched(try fixtureData(.en), at: field, 0xFFFF_FF00)) == nil)
}

@Test func missingFileIsNil() {
    #expect(BaseLexicon(url: fixtures.appendingPathComponent("missing.klex")) == nil)
}

@Test func corruptBodyFailsChecksumButReadsSafely() throws {
    var data = try fixtureData(.en)
    for i in stride(from: BaseLexicon.headerSize, to: data.count, by: 3) { data[i] ^= 0xA5 }
    let lexicon = try #require(BaseLexicon(data: data))
    #expect(!lexicon.verifyChecksum())
    let engine = Engine(lang: .en, lexicon: lexicon, layout: Layout.bundled("en-letters"))
    for typed in ["the", "hel", "leter", "x"] {
        #expect(engine.suggest(InputState(context: ["see", "you"], taps: taps(typed)), limit: 20).contains { $0.isLiteral })
    }
}
