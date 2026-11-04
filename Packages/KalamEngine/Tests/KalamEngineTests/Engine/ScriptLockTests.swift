import Foundation
import Testing
@testable import KalamEngine

// Research 2 (code-switching): each engine suggests and predicts in its own script only, even with
// a personal store that holds both scripts and with context from the other one.

private let mixedChats = Array(repeating: "ok habibi 3ashan kda يا حبيبي انا مش فاهم hello يا عم", count: 2)

private func isArabic(_ text: String) -> Bool { text.unicodeScalars.filter(\.properties.isAlphabetic).allSatisfy { $0.value >= 0x0600 && $0.value <= 0x06FF } }
private func isLatin(_ text: String) -> Bool { text.unicodeScalars.filter(\.properties.isAlphabetic).allSatisfy(\.isASCII) }

private func mixedEngines() throws -> (en: Engine, ar: Engine) {
    let model = PersonalModel(store: try personalStore(mixedChats), clock: epoch)
    func engine(_ lang: Lang) throws -> Engine {
        let lexicon = try #require(BaseLexicon(url: fixtures.appendingPathComponent("fixture-\(lang.rawValue).klex")))
        return Engine(lang: lang, lexicon: lexicon, layout: Layout.bundled("\(lang.rawValue)-letters"), personal: model)
    }
    return (try engine(.en), try engine(.ar))
}

@Test func arabicEngineSuggestsAndPredictsArabicOnly() throws {
    let ar = try mixedEngines().ar
    for context in [[], ["hello"], ["ok", "habibi"], ["يا"]] {
        for typed in ["ا", "يا", "حب", "مش", "عم"] {
            let texts = ar.candidates(InputState(context: context, taps: taps(typed, on: "ar-letters"))).map(\.text)
            #expect(!texts.isEmpty && texts.allSatisfy(isArabic), "\(typed) after \(context): \(texts)")
        }
        let predicted = ar.predict(context: context, limit: 50).map(\.text)
        #expect(!predicted.isEmpty && predicted.allSatisfy(isArabic), "after \(context): \(predicted)")
    }
}

@Test func englishEngineSuggestsAndPredictsLatinOnly() throws {
    let en = try mixedEngines().en
    for context in [[], ["حبيبي"], ["انا", "مش"], ["ok"]] {
        for typed in ["h", "ha", "hab", "ok", "kd", "a"] {
            let texts = en.candidates(InputState(context: context, taps: taps(typed))).map(\.text)
            #expect(!texts.isEmpty && texts.allSatisfy(isLatin), "\(typed) after \(context): \(texts)")
        }
        let predicted = en.predict(context: context, limit: 50).map(\.text)
        #expect(!predicted.isEmpty && predicted.allSatisfy(isLatin), "after \(context): \(predicted)")
    }
}

/// The current word can be an Arabic word on the EN page (the cursor moved after it): committing it
/// learns it as Arabic, so it never reaches the English tries.
@Test func aWordIsLearnedInItsOwnScriptWhateverThePage() throws {
    let store = try PersonalStore(url: temporaryStoreURL())
    let learner = Learner(store: store, model: nil, clock: epoch)
    learner.startSession(id: 1)
    learner.commit("حبيبي", lang: .en, context: ["hello"], how: .typed)
    learner.commit("habibi", lang: .ar, context: ["حبيبي"], how: .typed)
    learner.flush()
    #expect(try store.word(lang: "ar", ident: "حبيبي") != nil && store.word(lang: "en", ident: "حبيبي") == nil)
    #expect(try store.word(lang: "en", ident: "habibi") != nil && store.word(lang: "ar", ident: "habibi") == nil)
}
