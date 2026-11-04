import Foundation
import Testing
@testable import KalamEngine

private let start = Date(timeIntervalSinceReferenceDate: 0)

/// Adds the texts one second apart, oldest first.
private func history(_ texts: [String]) -> ClipboardHistory {
    var history = ClipboardHistory()
    for (i, text) in texts.enumerated() { history.add(text, now: start + Double(i)) }
    return history
}

@Test(arguments: ["", " \n\t", String(repeating: "a", count: ClipboardHistory.maxCharacters + 1)])
func blankAndOverlongTextsAreSkipped(_ text: String) {
    #expect(history([text]).items.isEmpty)
}

@Test func textAtTheLengthLimitIsKept() {
    #expect(history([String(repeating: "a", count: ClipboardHistory.maxCharacters)]).items.count == 1)
}

@Test func copyingAKnownTextMovesItToTheTopAndKeepsItsPin() {
    var clips = history(["one", "two"])
    clips.setPinned(true, text: "one")
    clips.add("one", now: start + 10)
    #expect(clips.items.map(\.text) == ["one", "two"])
    #expect(clips.items[0] == .init(text: "one", captured: start + 10, pinned: true))
}

@Test func panelShowsPinnedFirstThenNewestFirst() {
    var clips = history(["a", "b", "c", "d"])
    clips.setPinned(true, text: "b")
    clips.setPinned(true, text: "d")
    clips.setPinned(false, text: "d")
    #expect(clips.panelItems.map(\.text) == ["b", "d", "c", "a"])
}

@Test func deleteRemovesOneItemAndClearKeepsThePinned() {
    var clips = history(["a", "b", "c"])
    clips.setPinned(true, text: "a")
    clips.delete("b")
    #expect(clips.items.map(\.text) == ["c", "a"])
    clips.clear()
    #expect(clips.items.map(\.text) == ["a"])
}

@Test(arguments: [
    (age: 3600.0, pinned: false, kept: true),
    (age: 3601.0, pinned: false, kept: false),
    (age: 86_400.0, pinned: true, kept: true),
])
func unpinnedItemsExpireAfterAnHour(age: TimeInterval, pinned: Bool, kept: Bool) {
    var clips = history(["clip"])
    clips.setPinned(pinned, text: "clip")
    clips.expire(now: start + age)
    #expect(clips.items.isEmpty == !kept)
}

@Test func pastTheCapTheOldestUnpinnedGoFirst() {
    var clips = history(["pinned"])
    clips.setPinned(true, text: "pinned")
    for i in 0..<ClipboardHistory.maxItems { clips.add("clip \(i)", now: start + 1 + Double(i)) }
    #expect(clips.items.count == ClipboardHistory.maxItems)
    #expect(clips.items.contains { $0.text == "pinned" })
    #expect(!clips.items.contains { $0.text == "clip 0" })
}

@Test(arguments: [
    (age: 0.0, used: false, shown: true),
    (age: 120.0, used: false, shown: true),
    (age: 121.0, used: false, shown: false),
    (age: 5.0, used: true, shown: false),
])
func chipOffersAFreshUnusedClip(age: TimeInterval, used: Bool, shown: Bool) {
    var clips = history(["old", "new"])
    if used { clips.useChip() }
    #expect(clips.chip(now: start + 1 + age)?.text == (shown ? "new" : nil))
}

@Test func aNewClipBringsTheChipBack() {
    var clips = history(["first"])
    clips.useChip()
    clips.add("second", now: start + 5)
    #expect(clips.chip(now: start + 5)?.text == "second")
}

@Test func savedHistoryLoadsBackWithoutTheExpiredItems() {
    let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("clipboard.json")
    var clips = history(["old", "pinned old", "new"])
    clips.setPinned(true, text: "pinned old")
    clips.add("new", now: start + 3000)
    clips.useChip()
    clips.save(to: url)

    var expected = clips
    expected.delete("old")
    #expect(ClipboardHistory.load(from: url, now: start + 3700) == expected)
}

@Test(arguments: [nil, Data("not json".utf8)])
func missingOrCorruptFileIsAnEmptyHistory(_ contents: Data?) throws {
    let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("clipboard.json")
    if let contents { try contents.write(to: url) }
    #expect(ClipboardHistory.load(from: url, now: start) == ClipboardHistory())
}
