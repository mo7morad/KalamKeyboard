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

private func image(_ bytes: String, type: String = "public.png") -> ClipboardHistory.Image {
    ClipboardHistory.Image(data: Data(bytes.utf8), type: type)
}

private func texts(_ history: ClipboardHistory) -> [String?] {
    history.items.map { if case .text(let text) = $0.content { text } else { nil } }
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
    clips.setPinned(true, .text("one"))
    clips.add("one", now: start + 10)
    #expect(texts(clips) == ["one", "two"])
    #expect(clips.items[0] == .init(content: .text("one"), captured: start + 10, pinned: true))
}

@Test func anImageFileIsNamedByItsBytes() {
    #expect(image("cat") == image("cat"))
    #expect(image("cat").file != image("dog").file)
}

@Test func copyingAKnownImageMovesItToTheTopAndKeepsItsPin() {
    var clips = history(["text"])
    clips.add(image("cat"), now: start + 1)
    clips.setPinned(true, .image(image("cat")))
    clips.add("later", now: start + 2)
    clips.add(image("cat"), now: start + 10)
    #expect(clips.items.count == 3)
    #expect(clips.items[0] == .init(content: .image(image("cat")), captured: start + 10, pinned: true))
}

@Test func panelShowsPinnedFirstThenNewestFirst() {
    var clips = history(["a", "b", "c", "d"])
    clips.setPinned(true, .text("b"))
    clips.setPinned(true, .text("d"))
    clips.setPinned(false, .text("d"))
    #expect(clips.panelItems.map(\.content) == [.text("b"), .text("d"), .text("c"), .text("a")])
}

@Test func deleteRemovesOneItemAndClearKeepsThePinned() {
    var clips = history(["a", "b", "c"])
    clips.setPinned(true, .text("a"))
    clips.delete(.text("b"))
    #expect(texts(clips) == ["c", "a"])
    clips.clear()
    #expect(texts(clips) == ["a"])
}

@Test(arguments: [
    (age: 3600.0, pinned: false, kept: true),
    (age: 3601.0, pinned: false, kept: false),
    (age: 86_400.0, pinned: true, kept: true),
])
func unpinnedItemsExpireAfterAnHour(age: TimeInterval, pinned: Bool, kept: Bool) {
    var clips = ClipboardHistory()
    clips.add("clip", now: start)
    clips.add(image("cat"), now: start)
    clips.setPinned(pinned, .text("clip"))
    clips.setPinned(pinned, .image(image("cat")))
    clips.expire(now: start + age)
    #expect(clips.items.count == (kept ? 2 : 0))
}

@Test func pastTheCapTheOldestUnpinnedGoFirst() {
    var clips = history(["pinned"])
    clips.setPinned(true, .text("pinned"))
    clips.add(image("oldest"), now: start + 1)
    for i in 0..<ClipboardHistory.maxItems - 1 {
        if i.isMultiple(of: 2) { clips.add("clip \(i)", now: start + 2 + Double(i)) } else { clips.add(image("\(i)"), now: start + 2 + Double(i)) }
    }
    #expect(clips.items.count == ClipboardHistory.maxItems)
    #expect(clips.items.contains { $0.content == .text("pinned") })
    #expect(!clips.items.contains { $0.content == .image(image("oldest")) })
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
    #expect(clips.chip(now: start + 1 + age) == (shown ? "new" : nil))
}

@Test func aNewClipBringsTheChipBack() {
    var clips = history(["first"])
    clips.useChip()
    clips.add("second", now: start + 5)
    #expect(clips.chip(now: start + 5) == "second")
}

@Test func aCopiedImageGetsNoChip() {
    var clips = history(["text"])
    clips.add(image("cat"), now: start + 1)
    #expect(clips.chip(now: start + 1) == nil)
}

@Test func savedHistoryLoadsBackWithoutTheExpiredItems() {
    let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("clipboard.json")
    var clips = history(["old", "pinned old", "new"])
    clips.setPinned(true, .text("pinned old"))
    clips.add(image("cat", type: "public.jpeg"), now: start + 3000)
    clips.useChip()
    clips.save(to: url)

    var expected = clips
    expected.delete(.text("old"))
    expected.delete(.text("new"))
    #expect(ClipboardHistory.load(from: url, now: start + 3700) == expected)
}

@Test func aFileFromBeforeImagesStillLoads() throws {
    let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("clipboard.json")
    try Data(#"{"items":[{"text":"hello","captured":10,"pinned":true}],"chipUsed":false}"#.utf8).write(to: url)
    #expect(ClipboardHistory.load(from: url, now: start).items == [.init(content: .text("hello"), captured: start + 10, pinned: true)])
}

@Test(arguments: [nil, Data("not json".utf8)])
func missingOrCorruptFileIsAnEmptyHistory(_ contents: Data?) throws {
    let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("clipboard.json")
    if let contents { try contents.write(to: url) }
    #expect(ClipboardHistory.load(from: url, now: start) == ClipboardHistory())
}

@Test func filesOfDeletedAndExpiredImagesAreRemoved() throws {
    let folder = temporaryStoreURL().deletingLastPathComponent()
    let (deleted, expired, pinned) = (image("deleted"), image("expired"), image("pinned"))
    for name in [deleted, expired, pinned].flatMap({ [$0.file, $0.thumbnail] }) + ["stray"] {
        try Data().write(to: folder.appendingPathComponent(name))
    }
    var clips = ClipboardHistory()
    for added in [deleted, expired, pinned] { clips.add(added, now: start) }
    clips.setPinned(true, .image(pinned))
    clips.delete(.image(deleted))
    clips.expire(now: start + ClipboardHistory.lifetime + 1)

    clips.removeUnreferencedFiles(in: folder)
    let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(Set(left) == [pinned.file, pinned.thumbnail])
}
