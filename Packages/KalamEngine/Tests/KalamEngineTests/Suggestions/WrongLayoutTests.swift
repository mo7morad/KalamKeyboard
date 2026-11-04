import Foundation
import Testing
@testable import KalamEngine

private let en = Layout.bundled("en-letters")!, ar = Layout.bundled("ar-letters")!

/// A word of one page typed by position on the other: each tap lands where that letter sits on the
/// word's own page (its key center there) and types the nearest key of the page in use.
private func typedOnTheWrongPage(_ word: String, wordPage: Layout, page: Layout) -> [Tap] {
    let wordCenters = wordPage.keyCenters(), centers = page.keyCenters()
    return word.map { char in
        let point = wordPage.mapped(wordCenters[String(char)]!, to: page)
        let nearest = centers.min { hypot($0.value.x - point.x, $0.value.y - point.y) < hypot($1.value.x - point.x, $1.value.y - point.y) }!
        return Tap(nearest.key, at: point)
    }
}

private func rescue(_ engine: Engine, _ taps: [Tap], other: Engine, context: [String] = []) -> Suggestion? {
    let input = InputState(context: context, taps: taps)
    let ranked = engine.candidates(input)
    let autocorrect = engine.autocorrection(input, ranked: ranked, traits: FieldTraits(), settings: Settings())
    return engine.wrongLayoutRescue(input, ranked: ranked, autocorrect: autocorrect, other: other)
}

@Test func pointsMapByPhysicalPosition() {
    // Apple's iPhone pages, not the PC mapping: السلام by position on the EN page is gfafgk, not hgsghl.
    #expect(typedOnTheWrongPage("السلام", wordPage: ar, page: en).map(\.char).joined() == "gfafgk")
    #expect(typedOnTheWrongPage("شكرا", wordPage: ar, page: en).map(\.char).joined() == "albg")
    #expect(typedOnTheWrongPage("hello", wordPage: en, page: ar).map(\.char).joined() == "تثككح")
    let back = mappedTaps(typedOnTheWrongPage("السلام", wordPage: ar, page: en), from: en, to: ar)
    #expect(back?.map(\.char).joined() == "السلام")
    #expect(mappedTaps([Tap("g", at: Point(x: 5, y: 1.5)), Tap("3")], from: en, to: ar) == nil)  // a point-less tap can't be placed
}

@Test func arabicTypedOnTheEnglishPageIsRescued() throws {
    let (english, arabic) = (try fixtureEngine(.en), try fixtureEngine(.ar))
    #expect(rescue(english, typedOnTheWrongPage("السلام", wordPage: ar, page: en), other: arabic)?.text == "السلام")
    #expect(rescue(english, typedOnTheWrongPage("شكرا", wordPage: ar, page: en), other: arabic, context: ["ok"])?.text == "شكرا")
}

@Test func englishTypedOnTheArabicPageIsRescued() throws {
    let (english, arabic) = (try fixtureEngine(.en), try fixtureEngine(.ar))
    #expect(rescue(arabic, typedOnTheWrongPage("hello", wordPage: en, page: ar), other: english)?.text == "hello")
    #expect(rescue(arabic, typedOnTheWrongPage("tomorrow", wordPage: en, page: ar), other: english)?.text == "tomorrow")
}

@Test func aKnownPersonalWordOfTheOtherLanguageIsRescued() throws {
    let english = try fixtureEngine(.en)
    let arabic = try personalEngine(.ar, ["ماشي ماشي"])  // dialect, not in the base
    #expect(rescue(english, typedOnTheWrongPage("ماشي", wordPage: ar, page: en), other: arabic)?.text == "ماشي")
}

@Test func noRescueForWordsOfThePageInUse() throws {
    let (english, arabic) = (try fixtureEngine(.en), try fixtureEngine(.ar))
    #expect(rescue(english, taps("hello"), other: arabic) == nil)  // a valid word
    #expect(rescue(english, taps("helo"), other: arabic) == nil)  // autocorrected to hello
    #expect(rescue(arabic, taps("مدرسه", on: "ar-letters"), other: english) == nil)  // a same-key variant of مدرسة
    for chats in [["gfafgk gfafgk"], ["gfafgkoo gfafgkoo"]] {  // Moe's own word, or the start of one
        let known = try personalEngine(.en, chats)
        #expect(rescue(known, typedOnTheWrongPage("السلام", wordPage: ar, page: en), other: arabic) == nil, "\(chats)")
    }
    #expect(rescue(english, taps("tomo"), other: arabic) == nil)  // the start of tomorrow
}

@Test func noRescueWhenTheMappedTapsAreNoWordOrTooShortOrPointless() throws {
    let (english, arabic) = (try fixtureEngine(.en), try fixtureEngine(.ar))
    #expect(rescue(english, taps("qxzv"), other: arabic) == nil)  // no Arabic word at those spots
    #expect(rescue(english, typedOnTheWrongPage("يا", wordPage: ar, page: en), other: arabic) == nil)  // 2 letters
    var pointless = typedOnTheWrongPage("السلام", wordPage: ar, page: en)
    pointless[2] = Tap(pointless[2].char)
    #expect(rescue(english, pointless, other: arabic) == nil)
}
