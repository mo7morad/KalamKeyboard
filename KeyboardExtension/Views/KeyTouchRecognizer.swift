import UIKit
import UIKit.UIGestureRecognizerSubclass

/// How the keys get their touches (SPEC 5.2). A view's own touchesBegan is the last stop: the
/// keyboard window's system gesture recognizers can hold it back until they give up, and a touch
/// one of them claims never arrives (no haptic, no letter; device round 3: fast taps on changing
/// letters were lost). A gesture recognizer gets every touch first, as it happens, for every
/// finger, whatever the others do. This one never recognizes, so it never cancels or delays
/// anything, and no other recognizer can make it fail.
final class KeyTouchRecognizer: UIGestureRecognizer {
    var onBegan: (Set<UITouch>) -> Void = { _ in }
    /// With the event, for the samples coalesced into each move.
    var onMoved: (Set<UITouch>, UIEvent) -> Void = { _, _ in }
    var onEnded: (Set<UITouch>) -> Void = { _ in }
    var onCancelled: (Set<UITouch>) -> Void = { _ in }
    /// The touch sequence ended without an end or cancel for every touch (the view left its window).
    var onReset: () -> Void = {}

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onBegan(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        onMoved(touches, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        onEnded(touches)
        failAfterLastTouch(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        onCancelled(touches)
        failAfterLastTouch(event)
    }

    override func reset() {
        super.reset()
        onReset()
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /// It stays possible while any finger is down, so a finger that lands during a rollover always
    /// reaches it; after the last one lifts it fails, and UIKit resets it for the next touch.
    private func failAfterLastTouch(_ event: UIEvent) {
        if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) ?? true { state = .failed }
    }
}
