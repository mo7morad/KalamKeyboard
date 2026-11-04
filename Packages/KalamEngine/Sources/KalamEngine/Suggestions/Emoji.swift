import Foundation

/// SPEC 5.6: the emoji panel's categories and the bar's keyword lookup, from the bundled
/// emoji.json (built by Tools/emoji/build_emoji.py). Loaded once, on first use, from any thread.
public struct EmojiIndex: Decodable, Sendable {
    public struct Category: Decodable, Sendable {
        public let name: String
        public let emoji: [String]
    }

    public let categories: [Category]
    let keywords: [Lang: [String: [String]]]

    /// Empty when the resource is missing or malformed: no panel grid, no emoji suggestions.
    public static let shared: EmojiIndex = {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(EmojiIndex.self, from: data) else {
            return EmojiIndex(categories: [], keywords: [:])
        }
        return index
    }()

    init(categories: [Category], keywords: [Lang: [String: [String]]]) {
        (self.categories, self.keywords) = (categories, keywords)
    }

    private enum CodingKeys: CodingKey { case categories, keywords }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode([Category].self, forKey: .categories)
        let raw = try container.decode([String: [String: [String]]].self, forKey: .keywords)
        keywords = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Lang(rawValue: key).map { ($0, value) } })
    }

    /// The emoji whose name or keywords hold the word, best first.
    public func emoji(for word: String, lang: Lang) -> [String] {
        keywords[lang]?[normalize(word, lang: lang)] ?? []
    }
}

/// SPEC 5.6 Recents: the tapped emoji first, without its older copy, at most `limit`.
public func addingRecent(_ emoji: String, to recents: [String], limit: Int = 30) -> [String] {
    Array(([emoji] + recents.filter { $0 != emoji }).prefix(limit))
}
