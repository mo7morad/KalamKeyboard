import Testing
@testable import KalamEngine

@Test func bundledEmojiFollowsApplesCategoriesWithoutSkinTones() {
    let categories = EmojiIndex.shared.categories
    #expect(categories.map(\.name) == ["Smileys & People", "Animals & Nature", "Food & Drink", "Activity",
                                       "Travel & Places", "Objects", "Symbols", "Flags"])
    #expect(categories.first?.emoji.first == "😀")
    let all = categories.flatMap(\.emoji)
    #expect(all.contains("👋"))
    #expect(!all.contains("👋🏽"))
}

@Test(arguments: [
    ("Pizza", Lang.en, "🍕"), ("love", .en, "❤️"), ("coffee", .en, "☕"),
    ("قهوة", .ar, "☕"), ("حب", .ar, "❤️"),
])
func keywordsFindTheBestEmojiByNormalizedWord(word: String, lang: Lang, expected: String) {
    #expect(EmojiIndex.shared.emoji(for: word, lang: lang).first == expected)
}

@Test func functionWordsAndOtherLanguagesHaveNoEmoji() {
    #expect(EmojiIndex.shared.emoji(for: "the", lang: .en).isEmpty)
    #expect(EmojiIndex.shared.emoji(for: "pizza", lang: .ar).isEmpty)
}

@Test func recentsMoveATappedEmojiToTheFrontAndKeepThirty() {
    #expect(addingRecent("🍕", to: ["😀", "🍕", "❤️"]) == ["🍕", "😀", "❤️"])
    let full = (0..<30).map { String($0) }
    #expect(addingRecent("🍕", to: full).count == 30)
    #expect(addingRecent("🍕", to: full).last == "28")
}

@Test func anEmojiTakesAlt2MirroredForArabic() {
    let ranked = ["pizza", "pizzas", "piazza"].map {
        Suggestion(text: $0, ident: $0, isLiteral: $0 == "pizza", lm: 0, spatial: 0, edits: 0, completion: 0, boosts: 0)
    }
    let en = barSlots(ranked, autocorrect: nil, literal: "pizza", lang: .en, casing: .none, emoji: "🍕")
    #expect(en.map { $0?.label } == ["pizzas", "pizza", "🍕"])
    #expect(en[2]?.isEmoji == true)
    let ar = barSlots(ranked, autocorrect: nil, literal: "pizza", lang: .ar, casing: .none, emoji: "🍕")
    #expect(ar[0]?.label == "🍕")
}
