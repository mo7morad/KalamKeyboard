import Testing
@testable import KalamEngine

private func suggestion(_ text: String, literal: Bool = false) -> Suggestion {
    Suggestion(text: text, ident: text.lowercased(), isLiteral: literal, lm: 0, spatial: 0, edits: 0, completion: 0, boosts: 0)
}

@Test func pendingAutocorrectIsBoldWithTheQuotedLiteral() {
    let ranked = [suggestion("the"), suggestion("ten"), suggestion("teh", literal: true), suggestion("tech")]
    let slots = barSlots(ranked, autocorrect: ranked[0], literal: "teh", lang: .en, casing: .none)
    #expect(slots.map { $0?.label } == ["\u{201C}teh\u{201D}", "the", "ten"])
    #expect(slots.map { $0?.bold } == [false, true, false])
    #expect(slots[0]?.word == "teh")
    #expect(slots[0]?.isLiteral == true)
}

@Test func withoutAutocorrectTheSlotsHoldTheTopThree() {
    let ranked = [suggestion("going"), suggestion("goin", literal: true), suggestion("gone"), suggestion("good")]
    let slots = barSlots(ranked, autocorrect: nil, literal: "goin", lang: .en, casing: .firstLetter)
    #expect(slots.map { $0?.label } == ["Goin", "Going", "Gone"])
    #expect(slots.allSatisfy { $0?.bold == false })
}

@Test func capsLockShowsEverySlotInCapitals() {
    let ranked = [suggestion("the"), suggestion("ten"), suggestion("TEH", literal: true), suggestion("iPhone")]
    let pending = barSlots(ranked, autocorrect: ranked[0], literal: "TEH", lang: .en, casing: .all)
    #expect(pending.map { $0?.label } == ["\u{201C}TEH\u{201D}", "THE", "TEN"])
    let predictions = barSlots([suggestion("you"), suggestion("iPhone"), suggestion("the")], autocorrect: nil, literal: "", lang: .en, casing: .all)
    #expect(predictions.map { $0?.word } == ["IPHONE", "YOU", "THE"])
}

@Test func arabicMirrorsTheSlotsAndShortListsLeaveThemEmpty() {
    let ranked = [suggestion("أنا"), suggestion("انا", literal: true)]
    let slots = barSlots(ranked, autocorrect: nil, literal: "انا", lang: .ar, casing: .none)
    #expect(slots.map { $0?.label } == [nil, "أنا", "انا"])
    #expect(barSlots([], autocorrect: nil, literal: "", lang: .en, casing: .none) == [nil, nil, nil])
}

@Test func revertTakesThePrimaryAsTheQuotedLiteral() {
    let ranked = [suggestion("the", literal: true), suggestion("then"), suggestion("they")]
    for lang in [Lang.en, .ar] {
        let slots = barSlots(ranked, autocorrect: nil, literal: "the", lang: lang, casing: .none, revert: "teh")
        #expect(slots[1]?.label == "\u{201C}teh\u{201D}")
        #expect(slots[1]?.word == "teh")
        #expect(slots[1]?.isRevert == true && slots[1]?.isLiteral == true)
    }
}

@Test func rescueTakesAlt2OrAlt1WhenAnEmojiHoldsAlt2() {
    let ranked = [suggestion("gfafgk", literal: true), suggestion("gfa")]
    let rescue = suggestion("السلام", literal: true)  // the other engine's literal: here it's no quoted literal
    let slots = barSlots(ranked, autocorrect: nil, literal: "gfafgk", lang: .en, casing: .none, rescue: rescue)
    #expect(slots.map { $0?.label } == ["gfa", "gfafgk", "السلام"])
    #expect(slots[2]?.rescueLang == .ar && slots[2]?.isLiteral == false)
    let withEmoji = barSlots(ranked, autocorrect: nil, literal: "gfafgk", lang: .en, casing: .none, emoji: "👋", rescue: rescue)
    #expect(withEmoji.map { $0?.label } == ["السلام", "gfafgk", "👋"])
    let arabic = barSlots([suggestion("تثككح", literal: true)], autocorrect: nil, literal: "تثككح", lang: .ar, casing: .none,
                          rescue: suggestion("hello"))
    #expect(arabic.map { $0?.label } == ["hello", "تثككح", nil] && arabic[0]?.rescueLang == .en)
}

@Test func arabicVariantOfTheTypedKeyTakesAlt1() {
    let ranked = [suggestion("انا", literal: true), suggestion("انت"), suggestion("انها"), suggestion("أنا")]
    #expect(barSlots(ranked, autocorrect: nil, literal: "انا", lang: .ar, casing: .none).map { $0?.label } == ["انها", "انا", "أنا"])
    let shown = [suggestion("انا", literal: true), suggestion("أنا"), suggestion("انت"), suggestion("إنا")]
    #expect(barSlots(shown, autocorrect: nil, literal: "انا", lang: .ar, casing: .none).map { $0?.label } == ["انت", "انا", "أنا"])
    // A pending autocorrect keeps its quoted literal, and English has no variant slot.
    let pending = barSlots(ranked, autocorrect: ranked[1], literal: "انا", lang: .ar, casing: .none)
    #expect(pending.map { $0?.label } == ["انها", "انت", "\u{201C}انا\u{201D}"])
    let english = [suggestion("dont", literal: true), suggestion("done"), suggestion("dot"), suggestion("don't")]
    #expect(barSlots(english, autocorrect: nil, literal: "dont", lang: .en, casing: .none).map { $0?.label } == ["done", "dont", "dot"])
}
