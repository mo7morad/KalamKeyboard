#if DEBUG
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Debug builds only: sits on the keyboard's window, sees every touch the extension gets before any
/// view does, and traces it with the view it hit. Next to the key view's "touch" lines (same id),
/// a lost keystroke then shows whether it reached the extension at all (device round 3). It never
/// recognizes, delays or cancels anything.
final class TouchSpy: UIGestureRecognizer, UIGestureRecognizerDelegate {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    /// Once per window: the controller is recreated per host app, and the window may be reused.
    static func attach(to window: UIWindow?) {
        guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchSpy }) else { return }
        window.addGestureRecognizer(TouchSpy(target: nil, action: nil))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { log("began", touches) }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        log("ended", touches)
        failAfterLastTouch(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        log("cancelled", touches)
        failAfterLastTouch(event)
    }

    private func log(_ phase: String, _ touches: Set<UITouch>) {
        for touch in touches {
            let point = touch.location(in: nil)
            let view = touch.view.map { "\(type(of: $0))" } ?? "none"
            trace(String(format: "spy %@ at %.1f,%.1f in %@ lag %.1f ms id %@", phase, Double(point.x), Double(point.y), view,
                         (CACurrentMediaTime() - touch.timestamp) * 1000, "\(Unmanaged.passUnretained(touch).toOpaque())"))
        }
    }

    /// Stays possible while any finger is down, so it keeps seeing new touches through rollover.
    private func failAfterLastTouch(_ event: UIEvent) {
        if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) ?? true { state = .failed }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
#endif
