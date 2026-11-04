import XCTest

/// Captures Kalam's pages in the same host field as Apple's reference captures.
final class KalamCapture: XCTestCase {
    var app: XCUIApplication!
    /// Top of Kalam's key area on screen (view top + 44 pt bar); set from the element frame.
    var keyTop: CGFloat = 583

    func launch() {
        app = XCUIApplication()
        app.launch()
        sleep(2)
    }

    var kalam: XCUIElement { app.descendants(matching: .any)["kalam"] }

    func toKalam() {
        for _ in 0..<5 where !kalam.waitForExistence(timeout: 1.5) {
            let g = app.buttons["Next keyboard"]
            if g.exists { g.tap() }
            sleep(1)
        }
        XCTAssertTrue(kalam.exists)
        keyTop = kalam.frame.minY + 44
    }

    func at(_ x: CGFloat, row: Int) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: keyTop + 7 + 54 * CGFloat(row) + 22.5))
    }

    /// Center x of key `index` (in units from the left) on a page `units` wide.
    func x(_ unitsFromLeft: CGFloat, page units: CGFloat = 10) -> CGFloat { 3.5 + unitsFromLeft * (395 / units) }

    func tap(_ x: CGFloat, row: Int) { at(x, row: row).tap(); usleep(500_000) }

    func hold(_ x: CGFloat, row: Int, _ name: String, delay: Double = 1.0) {
        shotAsync(name, delay: delay)
        at(x, row: row).press(forDuration: delay + 1.0)
        while FileManager.default.fileExists(atPath: "\(base)/req/\(name)") { usleep(100_000) }
        usleep(300_000)
    }

    var pageID: String { kalam.value as? String ?? "" }

    func page(_ name: String) {
        XCTAssertEqual(pageID, name.replacingOccurrences(of: "-shifted", with: "-letters").replacingOccurrences(of: "-123", with: "-numbers"))
        try? app.debugDescription.write(toFile: "\(base)/dumps/kalam-\(name).txt", atomically: true, encoding: .utf8)
        shot("kalam-\(name)")
    }

    func testPages() {
        launch()
        toKalam()
        if pageID.hasPrefix("ar") { tap(x(2.0625, page: 11), row: 3) }
        page("en-shifted")
        tap(x(0.65), row: 2)                    // shift off
        page("en-letters")
        tap(x(0.625), row: 3)                   // 123
        page("en-123")
        tap(x(0.65), row: 2)                    // #+=
        page("en-symbols")
        tap(x(0.625), row: 3)                   // ABC
        hold(x(2.5), row: 0, "popup-e")
        hold(x(4.0), row: 1, "keypress-f", delay: 0.2)
        hold(x(0.5), row: 0, "keypress-q", delay: 0.2)
        tap(x(1.875), row: 3)                   // EN/AR
        page("ar-letters")
        hold(x(5.5, page: 11), row: 1, "popup-alef")
        tap(x(0.6875, page: 11), row: 3)        // ١٢٣
        page("ar-123")
        tap(x(0.65), row: 2)                    // #+=
        page("ar-symbols")
        tap(x(0.625), row: 3)                   // ابج
        tap(x(2.0625, page: 11), row: 3)        // EN/AR back to EN
    }

    func testEnableFullAccess() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        for label in ["General", "Keyboard", "KEYBOARDS"] {
            let cell = settings.cells[label].firstMatch.exists ? settings.cells[label].firstMatch : settings.staticTexts[label].firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5), label)
            cell.tap()
        }
        sleep(1)
        try? settings.debugDescription.write(toFile: "\(base)/dumps/keyboards.txt", atomically: true, encoding: .utf8)
        let kalam = settings.cells.containing(NSPredicate(format: "label CONTAINS 'Kalam'")).firstMatch
        guard kalam.waitForExistence(timeout: 5) else { XCTFail("no Kalam cell"); return }
        kalam.tap()
        let toggle = settings.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            sleep(1)
            try? settings.debugDescription.write(toFile: "\(base)/dumps/alert.txt", atomically: true, encoding: .utf8)
            let allow = settings.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
        }
        sleep(1)
        try? settings.debugDescription.write(toFile: "\(base)/dumps/settings.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(settings.switches.firstMatch.value as? String, "1")
    }
}
