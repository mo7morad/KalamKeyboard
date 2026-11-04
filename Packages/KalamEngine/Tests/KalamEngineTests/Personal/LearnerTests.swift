import Foundation
import Testing
@testable import KalamEngine

/// A learner on a fresh store, with a clock the test moves.
private final class Rig {
    var time = 0.0
    let url = temporaryStoreURL()
    let store: PersonalStore
    let model: PersonalModel
    let learner: Learner

    init() throws {
        store = try PersonalStore(url: url)
        var clock: () -> Date = { Date(timeIntervalSince1970: 0) }
        model = PersonalModel(store: store, clock: { clock() })
        learner = Learner(store: store, model: model, clock: { clock() })
        clock = { [unowned self] in Date(timeIntervalSince1970: time) }
        learner.startSession(id: 1)
    }

    func commit(_ words: String, lang: Lang = .en, how: Learner.Commit = .typed) {
        for word in words.split(separator: " ") { learner.commit(String(word), lang: lang, context: [], how: how) }
    }

    func state(_ ident: String, lang: String = "en") throws -> WordRow.State? { try store.word(lang: lang, ident: ident)?.state }
}

@Test func lastWordStaysPendingUntilTheNextCommit() throws {
    let rig = try Rig()
    rig.commit("hello")
    rig.time = 6
    rig.learner.writeIfDue()
    #expect(try rig.state("hello") == nil)
    rig.commit("there")
    #expect(try rig.state("hello") == .pending && rig.state("there") == nil)
}

@Test func finalEventsWaitForTheFlushInterval() throws {
    let rig = try Rig()
    rig.commit("one two three")
    #expect(try rig.state("one") == nil)
    rig.time = 5
    rig.learner.sentenceEnded()
    #expect(try rig.state("one") == .pending && rig.state("three") == .pending)
}

@Test func backspacingIntoThePendingWordDropsIt() throws {
    let rig = try Rig()
    rig.commit("hello")
    rig.learner.backspaced(into: "hello", lang: .en)
    rig.learner.flush()
    #expect(try rig.state("hello") == nil)
}

@Test func twoUsesInTwoSessionsMakeAWordSuggestable() throws {
    let rig = try Rig()
    rig.commit("kda")
    rig.learner.flush()
    rig.learner.startSession(id: 2)
    rig.commit("kda")
    rig.learner.flush()
    #expect(rig.model.isKnown(.en, "kda"))
}

@Test func tappingTheLiteralIsAnExplicitAccept() throws {
    let rig = try Rig()
    rig.commit("kda", how: .literal)
    rig.learner.flush()
    #expect(rig.model.isKnown(.en, "kda"))
}

@Test func undoingAnAutocorrectRejectsItAtOnceAndKeepsTheLiteral() throws {
    let rig = try Rig()
    rig.learner.commit("the", lang: .en, context: [], how: .autocorrect(from: "teh"))
    rig.learner.undoAutocorrect()
    #expect(rig.model.hasCorrection(.en, typed: "teh", chosen: "the", rejected: true))
    rig.learner.flush()
    #expect(try rig.state("teh") == .known && rig.state("the") == nil)
}

@Test(arguments: [
    ("hello", 9.0, true),  // edit distance 1, inside 10 s
    ("hello", 11.0, false),  // too late
    ("halloween", 3.0, false),  // too far apart
])
func manualCorrectionIsLearned(_ chosen: String, _ after: Double, _ learned: Bool) throws {
    let rig = try Rig()
    rig.commit("helo")
    rig.learner.backspaced(into: "helo", lang: .en)
    rig.time = after
    rig.commit(chosen)
    rig.learner.flush()
    #expect(rig.model.hasCorrection(.en, typed: "helo", chosen: chosen, rejected: false) == learned)
    #expect(try rig.state("helo") == nil)
}

@Test(arguments: [
    FieldTraits(keyboardType: .url), FieldTraits(contentType: .password), FieldTraits(contentType: .oneTimeCode),
])
func noLearningInSensitiveFields(_ traits: FieldTraits) throws {
    let rig = try Rig()
    rig.learner.traits = traits
    rig.commit("secret word")
    rig.learner.flush()
    #expect(try rig.state("secret") == nil)
}

@Test func pauseLearningStopsLearning() throws {
    let rig = try Rig()
    rig.learner.paused = true
    rig.commit("secret word")
    rig.learner.flush()
    #expect(try rig.state("secret") == nil)
}

@Test func specialTokensAreLearnedAsTok() throws {
    let rig = try Rig()
    rig.commit("me@x.com", how: .literal)
    rig.learner.flush()
    #expect(try rig.state("me@x.com", lang: "tok") == .known)
}

@Test func contextFromAnotherLanguageIsDropped() throws {
    let rig = try Rig()
    rig.learner.commit("يا", lang: .ar, context: ["ok"], how: .typed)
    rig.learner.commit("عم", lang: .ar, context: ["ok", "يا"], how: .typed)
    rig.learner.flush()
    #expect(try rig.store.continuations(lang: "ar", w1: "", w2: "ok").isEmpty)
    #expect(try rig.store.continuations(lang: "ar", w1: "", w2: "يا").keys.sorted() == ["عم"])
}

@Test func lexiconEntriesBecomeKnownWords() throws {
    let rig = try Rig()
    rig.learner.addLexiconEntries(["Omar Khaled", "On my way!"])
    #expect(try ["omar", "khaled", "way"].map { try rig.state($0) } == [.known, .known, .known])
}

@Test func failedWriteIsRetriedWithoutLoss() throws {
    let rig = try Rig()
    rig.commit("hello")
    let blocker = try SQLite(url: rig.url)
    try blocker.execute("BEGIN IMMEDIATE")
    rig.learner.flush()
    try blocker.execute("COMMIT")
    #expect(try rig.state("hello") == nil)
    rig.learner.flush()
    #expect(try rig.store.word(lang: "en", ident: "hello")?.hits.count == 1)
}

@Test func anAutocorrectCommittedByASentenceEndCanStillBeUndone() throws {
    let rig = try Rig()
    rig.learner.commit("the", lang: .en, context: [], how: .autocorrect(from: "teh"))
    rig.learner.sentenceEnded()  // "teh." or "teh" + return
    rig.learner.undoAutocorrect()
    #expect(rig.model.hasCorrection(.en, typed: "teh", chosen: "the", rejected: true))
}
