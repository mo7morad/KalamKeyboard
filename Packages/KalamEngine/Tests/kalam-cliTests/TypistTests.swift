import Testing
@testable import kalam_cli

/// The next word is the one after it in the same run: not across a sentence end or a change of script.
@Test func eachWordGetsTheWordAfterItInItsRun() {
    let next = wordsWithNext("the quick fox. ok يا").map { "\($0.token.surface)>\($0.next ?? "-")" }
    #expect(next == ["the>quick", "quick>fox", "fox>-", "ok>-", "يا>-"])
}
