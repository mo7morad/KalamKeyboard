import UIKit
import XCTest

/// SPEC 5.5 checks on the harness field: the clip chip, then the panel (paste, pin, delete).
/// The runner writes the pasteboard itself; Kalam captures on appear and when the panel opens.
final class ClipboardCheck: KalamField {
    var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    var clipboardButton: XCUICoordinate { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 22, dy: keyTop - 22)) }
    /// Tile `index` in the two-column grid right under the bar (8 pt inset, 72 pt tiles).
    func tile(_ index: Int) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: index % 2 == 0 ? 102 : 300, dy: keyTop + 8 + 36 + 80 * CGFloat(index / 2)))
    }
    func dump(_ name: String) {
        try? app.debugDescription.write(toFile: "\(base)/dumps/\(name).txt", atomically: true, encoding: .utf8)
        try? springboard.debugDescription.write(toFile: "\(base)/dumps/\(name)-springboard.txt", atomically: true, encoding: .utf8)
    }
    /// Notes and answers iOS's paste prompt, if one shows.
    func answerPastePrompt(_ label: String) {
        let allow = springboard.buttons["Allow Paste"]
        log += "\(label) prompt: \(allow.waitForExistence(timeout: 2))\n"
        if allow.exists { shot("clip-prompt"); allow.tap() }
    }

    /// Expect the chip after a copy, and a tap on it pasting the clip.
    func testChipThenPanel() {
        UIPasteboard.general.string = "Meet me at 7 by the station"
        launchKalam()
        answerPastePrompt("appear")
        sleep(1)
        dump("clip-chip")
        shot("clip-chip")
        primarySlot.tap()
        sleep(1)
        note("after chip")

        UIPasteboard.general.string = "Second clip\nwith a second line\nand a third\nand a fourth"
        clipboardButton.tap()  // opens the panel, which captures
        answerPastePrompt("panel")
        sleep(1)
        UIPasteboard.general.string = "Third clip"
        clipboardButton.tap()  // closes
        sleep(1)
        clipboardButton.tap()  // opens again: captures the third
        sleep(1)
        dump("clip-panel")
        shot("clip-panel")
        tile(1).tap()  // "Second clip": pasted, panel stays open
        sleep(1)
        note("after tile")
        tile(2).press(forDuration: 1.0)  // the chip's clip: Pin / Delete
        sleep(1)
        shot("clip-actions")
        tile(2).withOffset(CGVector(dx: -47, dy: 0)).tap()  // Pin (left half)
        sleep(1)
        shot("clip-pinned")
        tile(1).press(forDuration: 1.0)
        sleep(1)
        tile(1).withOffset(CGVector(dx: 47, dy: 0)).tap()  // Delete (right half)
        sleep(1)
        dump("clip-after")
        shot("clip-after")
        note("end, panel value \(pageID)")
    }

    /// Arabic letters behind the panel, an Arabic tile right-aligned.
    func testPanelArabic() {
        UIPasteboard.general.string = "مساء الخير، هنتقابل الساعة سبعة"
        launchKalam()
        answerPastePrompt("appear")
        tap(1.875, 3)  // EN/AR
        sleep(1)
        clipboardButton.tap()
        sleep(1)
        shot("clip-panel-ar")
        clipboardButton.tap()
        tap(2.0625, 3, units: 11)  // back to EN
    }

    /// Records Settings › Apps › Kalam, then sets "Paste from Other Apps" to Allow.
    func testAllowPaste() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        for label in ["Apps", "Kalam"] {
            let cell = settings.cells[label].firstMatch.exists ? settings.cells[label].firstMatch : settings.staticTexts[label].firstMatch
            for _ in 0..<6 where !cell.isHittable { settings.swipeUp() }
            if cell.waitForExistence(timeout: 3) { cell.tap() }
            sleep(1)
        }
        try? settings.debugDescription.write(toFile: "\(base)/dumps/settings-kalam.txt", atomically: true, encoding: .utf8)
        shot("settings-kalam")
        settings.staticTexts["Paste from Other Apps"].firstMatch.tap()
        sleep(1)
        settings.staticTexts["Allow"].firstMatch.tap()
        sleep(1)
        shot("settings-paste-allow")
    }
}
