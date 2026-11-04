import XCTest

/// The harness field with Kalam picked from the globe's list, and tap helpers in key units.
/// Field texts go to `base`/values.txt, screenshots through the watcher.
class KalamField: XCTestCase {
    var app: XCUIApplication!
    var keyTop: CGFloat = 0
    var kalam: XCUIElement { app.descendants(matching: .any)["kalam"] }
    var field: XCUIElement { app.textViews["field"] }
    var log = ""
    var pageID: String { kalam.value as? String ?? "" }

    /// Launches the harness and selects Kalam (the globe's tap cycles only Apple's keyboards).
    func launchKalam(_ arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        sleep(2)
        if !kalam.exists {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 33, dy: 830)).press(forDuration: 1.2)
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Kalam'")).firstMatch.tap()
        }
        XCTAssertTrue(kalam.waitForExistence(timeout: 5))
        keyTop = kalam.frame.minY + 40
        if pageID.hasPrefix("ar") { tap(2.0625, 3, units: 11) }
        tap(0.65, 2)  // shift off
    }

    func at(_ u: CGFloat, row: Int, units: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 3.5 + u * (395 / units), dy: keyTop + 7 + 54 * CGFloat(row) + 22.5))
    }
    func tap(_ u: CGFloat, _ row: Int, units: CGFloat = 10) { at(u, row: row, units: units).tap(); usleep(450_000) }
    var primarySlot: XCUICoordinate { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 201, dy: keyTop - 22)) }
    func note(_ label: String) {
        log += "\(label): [\(field.value as? String ?? "<nil>")]\n"
        try? log.write(toFile: "\(base)/values.txt", atomically: true, encoding: .utf8)
    }

}

/// Phase 5 end-to-end checks: autocorrect and its undo, picks, punctuation spacing and blocking.
final class Phase5: KalamField {
    /// Expect "teh" + space -> "the ", then one backspace -> "teh", then an Arabic word.
    func testTypoUndoArabic() {
        launchKalam()
        tap(4.5, 0); tap(2.5, 0); tap(6.0, 1)  // t e h
        sleep(1)
        shot("bar-en-typing")
        note("typed")
        tap(5.0, 3)  // space
        sleep(1)
        note("after space")
        shot("bar-en-after-space")
        tap(9.35, 2)  // backspace
        sleep(1)
        note("after backspace")
        tap(5.0, 3)  // space: keeps teh
        tap(8.75, 3)  // return
        tap(1.875, 3)  // EN/AR
        sleep(1)
        for u in [5.5, 7.5, 5.5] as [CGFloat] { tap(u, 1, units: 11) }  // ا ن ا
        sleep(1)
        shot("bar-ar-typing")
        note("arabic typed")
        tap(4.812, 3, units: 11)  // space
        sleep(1)
        note("arabic after space")
        tap(2.0625, 3, units: 11)  // back to EN
    }

    /// Expect a picked suggestion plus auto-space, then "," replacing that space, then the block overlay.
    func testPickPunctuationBlock() {
        launchKalam()
        tap(6.0, 1); tap(2.5, 0); tap(9.0, 1)  // h e l
        sleep(1)
        primarySlot.tap()
        sleep(1)
        note("after pick")
        tap(0.625, 3)  // 123
        tap(3.6, 2)  // ,
        sleep(1)
        note("after comma")
        primarySlot.press(forDuration: 1.0)
        sleep(1)
        shot("block-overlay")
    }
}
