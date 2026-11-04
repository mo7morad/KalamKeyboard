import Testing
@testable import KalamEngine

private func suggestion(_ text: String, literal: Bool = false) -> Suggestion {
    Suggestion(text: text, ident: text.lowercased(), isLiteral: literal, lm: 0, spatial: 0, edits: 0, completion: 0, boosts: 0)
}

@Test func pendingAutocorrectIsBoldWithTheQuotedLiteral() {
    let ranked = [suggestion("the"), suggestion("ten"), suggestion("teh", literal: true), suggestion("tech")]
    let slots = barSlots(ranked, autocorrect: ranked[0], literal: "teh", lang: .en, capitalized: false)
    #expect(slots.map { $0?.label } == ["\u{201C}teh\u{201D}", "the", "ten"])
    #expect(slots.map { $0?.bold } == [false, true, false])
    #expect(slots[0]?.word == "teh")
    #expect(slots[0]?.isLiteral == true)
}

@Test func withoutAutocorrectTheSlotsHoldTheTopThree() {
    let ranked = [suggestion("going"), suggestion("goin", literal: true), suggestion("gone"), suggestion("good")]
    let slots = barSlots(ranked, autocorrect: nil, literal: "goin", lang: .en, capitalized: true)
    #expect(slots.map { $0?.label } == ["Goin", "Going", "Gone"])
    #expect(slots.allSatisfy { $0?.bold == false })
}

@Test func arabicMirrorsTheSlotsAndShortListsLeaveThemEmpty() {
    let ranked = [suggestion("أنا"), suggestion("انا", literal: true)]
    let slots = barSlots(ranked, autocorrect: nil, literal: "انا", lang: .ar, capitalized: false)
    #expect(slots.map { $0?.label } == [nil, "أنا", "انا"])
    #expect(barSlots([], autocorrect: nil, literal: "", lang: .en, capitalized: false) == [nil, nil, nil])
}
