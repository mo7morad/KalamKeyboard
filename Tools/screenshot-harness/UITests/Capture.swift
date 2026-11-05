import XCTest

let base = "/private/tmp/claude-501/-Users-mohamedmorad-Developer-Extras-myKeyboard/8701a34a-f0c6-491e-9052-3cc4a54dfb6e/scratchpad/capture"

/// Asks the shell watcher for a screenshot after `delay` s and blocks until it is taken.
func shot(_ name: String, delay: Double = 0.8) {
    let p = "\(base)/req/\(name)"
    try! "\(delay)".write(toFile: p, atomically: true, encoding: .utf8)
    while FileManager.default.fileExists(atPath: p) { usleep(100_000) }
}

/// Requests a screenshot `delay` s from now without blocking (for use during a hold).
func shotAsync(_ name: String, delay: Double) {
    try! "\(delay)".write(toFile: "\(base)/req/\(name)", atomically: true, encoding: .utf8)
}

class Capture: XCTestCase {
    var app: XCUIApplication!
    var kb: XCUIElement { app.keyboards.firstMatch }

    func dump(_ name: String) {
        try? app.debugDescription.write(toFile: "\(base)/dumps/\(name).txt", atomically: true, encoding: .utf8)
    }

    /// First keyboard key or button whose label or identifier matches one of `names`.
    func el(_ names: [String]) -> XCUIElement? {
        for n in names {
            let p = NSPredicate(format: "label == %@ OR identifier == %@", n, n)
            for q in [kb.keys, kb.buttons, app.keys, app.buttons] {
                let e = q.matching(p).firstMatch
                if e.exists && e.isHittable { return e }
            }
        }
        return nil
    }

    func tap(_ names: String..., file: StaticString = #filePath, line: UInt = #line) {
        guard let e = el(names) else { dump("FAIL-\(names[0])"); XCTFail("no key \(names)", file: file, line: line); return }
        e.tap(); usleep(400_000)
    }

    /// Taps a page-switch key, retrying because the first tap after a keyboard switch can be swallowed.
    func go(_ names: [String], until expect: String) {
        for _ in 0..<3 {
            if el([expect]) != nil { return }
            if let e = el(names) { e.tap() }
            sleep(1)
        }
        if el([expect]) == nil { dump("FAIL-go-\(expect)"); XCTFail("page with \(expect) not reached") }
    }

    func page(_ name: String) { dump(name); shot(name) }

    func longPress(_ label: String, _ name: String) {
        guard let e = el([label]) else { dump("FAIL-\(name)"); XCTFail("no key \(label)"); return }
        shotAsync(name, delay: 1.8)
        e.press(forDuration: 3.2)
        while FileManager.default.fileExists(atPath: "\(base)/req/\(name)") { usleep(100_000) }
        usleep(300_000)
    }

    func launch(_ args: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(kb.waitForExistence(timeout: 10))
        sleep(2)
    }

    func globe() {
        if let g = el(["Next keyboard", "globe", "Globe", "nextKeyboard"]) { g.tap() }
        else { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 33, dy: 830)).tap() }
        sleep(1)
    }

    /// Types by tapping the on-screen keys so the predictive bar updates (typeText bypasses it).
    func typeKeys(_ text: String) {
        for ch in text {
            let c = String(ch)
            if c == " " { tap("space"); continue }
            guard let e = el([c, c.uppercased(), c.lowercased()]) else { dump("FAIL-type-\(c)"); XCTFail("no key \(c)"); return }
            e.tap(); usleep(250_000)
        }
    }

    var isArabic: Bool { el(["ا"]) != nil }

    func testEnglish() {
        launch()
        if isArabic { globe() }
        page("en-shifted")
        tap("shift")
        page("en-letters")
        go(["more"], until: "1")
        page("en-123")
        go(["symbols", "#+=", "more, symbols", "الرموز"], until: "#")
        page("en-symbols")
        go(["more"], until: "q")
        for (k, n) in [("e", "popup-e"), ("a", "popup-a"), ("u", "popup-u"), ("n", "popup-n"), ("c", "popup-c")] { longPress(k, n) }
        // key-press preview: brief hold on a key with no alternates
        for k in ["q", "b", "f"] { longPress(k, "probe-\(k)") }
        for k in ["q", "b", "f"] { if let e = el([k]) { shotAsync("keypress-\(k)", delay: 0.2); e.press(forDuration: 1.0); sleep(1) } }
        app.terminate()

        launch()
        typeKeys("I am going to the ")
        sleep(1); page("suggestions-en")
        typeKeys("sto")
        sleep(1); page("suggestions-en-typing")
        app.terminate()

        launch(["-noPredict"])
        tap("shift")
        page("en-letters-nobar")
    }

    func testArabic() {
        launch()
        if !isArabic { globe() }
        XCTAssertTrue(isArabic)
        page("ar-letters")
        go(["more"], until: "١")
        page("ar-123")
        go(["symbols", "#+=", "more, symbols", "الرموز"], until: "#")
        page("ar-symbols")
        go(["more"], until: "ا")
        for (k, n) in [("ا", "popup-alef"), ("ي", "popup-yeh"), ("و", "popup-waw"), ("ه", "popup-heh")] { longPress(k, n) }
        if let k = el(["ك"]) { shotAsync("keypress-kaf", delay: 0.2); k.press(forDuration: 1.0); sleep(1) }
        app.terminate()

        launch()
        if !isArabic { globe() }
        typeKeys("انا رايح ")
        sleep(1); page("suggestions-ar")
        app.terminate()

        launch(["-noPredict"])
        if !isArabic { globe() }
        page("ar-letters-nobar")
        globe() // leave English selected for the next run
    }
}
