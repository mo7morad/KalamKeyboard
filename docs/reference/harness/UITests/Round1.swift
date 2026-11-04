import XCTest

/// Device round 1: Apple's tashkeel strip (the tanween key held down).
final class AppleTashkeel: Capture {
    func testTashkeel() {
        launch()
        for _ in 0..<6 where !isArabic { globe() }
        longPress("ً", "popup-tashkeel")
    }
}

/// Device round 1: Kalam's tashkeel strip, then a short typing run that fills the Debug trace.
final class Round1: KalamField {
    func testTashkeelAndTyping() {
        launchKalam()
        tap(1.875, 3)  // EN/AR
        shotAsync("kalam-popup-tashkeel", delay: 1.0)
        at(7.5625, row: 3, units: 11).press(forDuration: 2.0)  // tanween, released without sliding
        while FileManager.default.fileExists(atPath: "\(base)/req/kalam-popup-tashkeel") { usleep(100_000) }
        sleep(1)
        note("after tashkeel")
        tap(2.0625, 3, units: 11)  // back to EN
        for (u, row) in [(6.0, 1), (7.5, 0), (5.0, 3), (4.5, 0), (2.5, 0), (6.0, 1), (5.0, 3)] as [(CGFloat, Int)] { tap(u, row) }  // "hi teh "
        sleep(1)
        note("after typing")
        field.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: 12)).tap()  // moves the cursor: a host change
        sleep(1)
        for u in [0.5, 9.5, 0.5, 9.5] as [CGFloat] { tap(u, 0) }  // edge keys q p q p: compare their lag
        note("after edges")
    }
}
