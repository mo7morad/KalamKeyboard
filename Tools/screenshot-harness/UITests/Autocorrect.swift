import XCTest

/// Phase 19: Apple's autocorrect states in the bar. Run once per appearance; `values.txt` gets the
/// field text and bar labels at each step. Run under `simctl io recordVideo` to see the animations.
final class AppleAutocorrect: Capture {
    var field: XCUIElement { app.textViews["field"] }
    var log = ""

    func note(_ label: String) {
        let bar = app.descendants(matching: .any).matching(identifier: "Typing Predictions").firstMatch
        let cells = bar.exists ? bar.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty } : []
        log += "\(label): [\(field.value as? String ?? "<nil>")] bar \(cells)\n"
        try? log.write(toFile: "\(base)/values-apple.txt", atomically: true, encoding: .utf8)
    }

    /// Launches the field and cycles the globe until one of Apple's keyboards shows (not Kalam).
    func start() {
        app = XCUIApplication()
        app.launch()
        sleep(2)
        for _ in 0..<5 where !(kb.exists && el(["space"]) != nil) {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 42, dy: 840)).tap()
            sleep(1)
        }
    }

    func step(_ name: String) { sleep(1); note(name); dump("autocorrect-\(name)"); shot("autocorrect-\(name)", delay: 0.2) }

    /// Types `typo`, then space, backspace, and finally taps back into the corrected word.
    func run(_ typo: String, _ tag: String) {
        typeKeys(typo)
        step("\(tag)-pending")
        tap("space")
        step("\(tag)-corrected")
        tap("delete", "حذف", "Delete")
        step("\(tag)-undo")
        typeKeys(" ok ")
        // The end of the first word. On "The" this only brought up the edit menu (see the README).
        field.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: 20)).tap()
        step("\(tag)-revert")
    }

    func testAutocorrectEnglish() {
        for (typo, tag) in [("teh", "en"), ("recieve", "en-recieve")] {
            start()
            for _ in 0..<4 where isArabic { globe() }
            if el(["shift"])?.value as? String == "1" { tap("shift") }
            run(typo, tag)
            app.terminate()
        }
    }

    func testAutocorrectArabic() {
        start()
        for _ in 0..<4 where !isArabic { globe() }
        typeKeys("السلان")
        step("ar-pending")
        tap("space")
        step("ar-corrected")
        tap("delete", "حذف", "Delete")
        step("ar-undo")
        typeKeys(" عليكم ")
        field.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0)).withOffset(CGVector(dx: -30, dy: 20)).tap()
        step("ar-revert")
        globe()
    }
}

/// Phase 19: Kalam in the same states as `AppleAutocorrect`. Kalam's backspace puts the literal
/// back (SPEC 8.5), which records a rejection, so the undo comes last and the personal store is
/// deleted before each run (`personal.sqlite*` in the App Group container). Arabic autocorrect must
/// be normal, Moe's setting (`autocorrectAR` = normal in the group defaults), or السلان stays.
final class KalamAutocorrect: KalamField {
    func step(_ name: String) {
        sleep(1)
        note(name)
        shot("kalam-autocorrect-\(name)", delay: 0.2)
    }
    var space: (CGFloat, Int, CGFloat) { pageID.hasPrefix("ar") ? (4.812, 3, 11) : (5.0, 3, 10) }
    var backspace: (CGFloat, Int, CGFloat) { pageID.hasPrefix("ar") ? (10.3, 2, 11) : (9.35, 2, 10) }
    func type(_ keys: [(CGFloat, Int)], units: CGFloat = 10) { for (u, row) in keys { tap(u, row, units: units) } }
    func press(_ key: (CGFloat, Int, CGFloat)) { tap(key.0, key.1, units: key.2) }

    /// Phase 22: alt1 (left in EN, right in AR) holds the revert offer right after a correction.
    /// The slots start after the clipboard and emoji buttons (88 pt) and share the rest (402 pt wide).
    var alt1: XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: pageID.hasPrefix("ar") ? 350 : 140, dy: keyTop - 22))
    }

    /// Pending, the revert offer right after the space and after it times out, the offer with the
    /// cursor back after the word, then the undo.
    func run(_ typo: [(CGFloat, Int)], _ tag: String, units: CGFloat = 10, ok: [(CGFloat, Int)], wordEnd: CGVector) {
        type(typo, units: units)
        step("\(tag)-pending")
        press(space)
        step("\(tag)-offer")
        sleep(3)
        step("\(tag)-offer-expired")
        type(ok, units: units)
        press(space)
        // Twice: a tap sometimes only brings up the edit menu; one on the caret leaves it in place.
        for _ in 0..<2 {
            field.coordinate(withNormalizedOffset: wordEnd.dx < 0 ? CGVector(dx: 1, dy: 0) : .zero).withOffset(wordEnd).tap()
            sleep(1)
        }
        step("\(tag)-revert")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()  // back to the end, after "ok "
        type(typo, units: units)
        press(space)
        press(backspace)
        step("\(tag)-undo")
    }

    /// Each word on a fresh launch: after a cursor move the host's text before the cursor stops at a
    /// new line, and the revert offer needs the same text before the word as when it was corrected.
    func testAutocorrect() {
        let ok: [(CGFloat, Int)] = [(8.5, 0), (8.0, 1)]
        launchKalam()
        run([(4.5, 0), (2.5, 0), (6.0, 1)], "en", ok: ok, wordEnd: CGVector(dx: 24, dy: 20))
        launchKalam()
        run([(3.5, 0), (2.5, 0), (4.0, 2), (7.5, 0), (2.5, 0), (5.0, 2), (2.5, 0)], "en-recieve", ok: ok, wordEnd: CGVector(dx: 60, dy: 20))
        launchKalam()
        tap(1.875, 3)  // EN/AR
        sleep(1)
        // السلان, then عليكم; RTL, so the word ends on its left. Needs autocorrectAR = normal (Moe's setting).
        run([(5.5, 1), (4.5, 1), (1.5, 1), (4.5, 1), (5.5, 1), (7.5, 1)], "ar", units: 11,
            ok: [(6.5, 0), (4.5, 1), (2.5, 1), (9.5, 1), (8.5, 1)], wordEnd: CGVector(dx: -45, dy: 20))
        tap(2.0625, 3, units: 11)  // back to EN
    }

    /// Phase 22: a tap on the offer right after the space puts the literal back, keeping the space.
    /// Records the rejection, so run it on its own store (not before `testAutocorrect`).
    func testOfferTap() {
        launchKalam()
        type([(4.5, 0), (2.5, 0), (6.0, 1)])  // teh
        press(space)
        sleep(1)
        alt1.tap()
        step("en-offer-tapped")
        tap(1.875, 3)  // EN/AR
        sleep(1)
        type([(5.5, 1), (4.5, 1), (1.5, 1), (4.5, 1), (5.5, 1), (7.5, 1)], units: 11)  // السلان
        press(space)
        sleep(1)
        alt1.tap()
        step("ar-offer-tapped")
        tap(2.0625, 3, units: 11)  // back to EN
    }
}
