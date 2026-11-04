import XCTest

/// Long-presses Apple's EN keys whose alternates Phase 1 missed.
final class Accents: Capture {
    func testAccents() {
        launch()
        for _ in 0..<6 {
            let kalam = app.descendants(matching: .any)["kalam"].exists
            if !kalam, !isArabic, el(["i", "I"]) != nil { break }
            globe()
        }
        dump("accents")
        if el(["i"]) == nil, el(["I"]) != nil { tap("shift") }
        for k in ["i", "o", "s", "y", "z", "l"] { longPress(k, "accent-\(k)") }
    }
}
