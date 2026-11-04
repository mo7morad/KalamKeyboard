import UIKit

/// The key-press bubble and the long-press alternates strip, sized from the captures
/// (keypress-f, popup-e). A keyboard extension can't draw above its own view, so popups over
/// the top row are pushed down to stay inside it.
final class PopupLayers {
    let bubble = CALayer()
    let strip = CALayer()
    var scale: CGFloat = 3

    private let bubbleGlyph = CALayer()
    private let selection = CALayer()
    private var stripItemWidth: CGFloat = 0
    private var stripItems: [CALayer] = []

    /// Gap between a popup's bottom and the top of the pressed key's cap.
    private static let lift: CGFloat = 2.7
    private static let bubbleExtraWidth: CGFloat = 21.5
    private static let bubbleHeight: CGFloat = 66
    private static let stripPadding: CGFloat = 13
    private static let stripItemExtraWidth: CGFloat = 5
    private static let edgeInset: CGFloat = 3.5

    init() {
        for layer in [bubble, strip] {
            layer.isHidden = true
            layer.cornerCurve = .continuous
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 4
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.zPosition = 1
        }
        bubble.cornerRadius = 12
        strip.cornerRadius = 24
        bubble.addSublayer(bubbleGlyph)
        selection.cornerRadius = 8
        selection.cornerCurve = .continuous
        strip.addSublayer(selection)
    }

    func showBubble(over cap: CGRect, image: CGImage?, palette: Palette) {
        withoutAnimation {
            let width = cap.width + Self.bubbleExtraWidth
            bubble.frame = CGRect(x: cap.midX - width / 2, y: max(0, cap.minY - Self.lift - Self.bubbleHeight),
                                  width: width, height: Self.bubbleHeight)
            bubble.backgroundColor = palette.bubble.cgColor
            place(image, in: bubbleGlyph, center: CGPoint(x: width / 2, y: Self.bubbleHeight / 2))
            bubble.isHidden = false
        }
    }

    func hideBubble() { withoutAnimation { bubble.isHidden = true } }
    func hideStrip() { withoutAnimation { strip.isHidden = true } }

    /// Lays the items out left to right with `selected` centered over the key where the edges allow;
    /// items narrow when the strip would be wider than the keyboard.
    func showStrip(items: [String], selected: Int, over cap: CGRect, in bounds: CGRect,
                   glyph: (String) -> CGImage?, palette: Palette) {
        withoutAnimation {
            let room = bounds.width - 2 * (Self.edgeInset + Self.stripPadding)
            stripItemWidth = min(cap.width + Self.stripItemExtraWidth, room / CGFloat(items.count))
            let width = CGFloat(items.count) * stripItemWidth + 2 * Self.stripPadding
            let height = cap.height + 2 * Self.stripPadding
            var x = cap.midX - Self.stripPadding - (CGFloat(selected) + 0.5) * stripItemWidth
            x = min(max(x, Self.edgeInset), bounds.width - Self.edgeInset - width)
            strip.frame = CGRect(x: x, y: max(0, cap.minY - Self.lift - height), width: width, height: height)
            strip.backgroundColor = palette.strip.cgColor
            stripItems.forEach { $0.removeFromSuperlayer() }
            stripItems = items.enumerated().map { index, item in
                let layer = CALayer()
                place(glyph(item), in: layer, center: CGPoint(x: itemFrame(index).midX, y: height / 2))
                strip.addSublayer(layer)
                return layer
            }
            select(selected, palette: palette)
            strip.isHidden = false
        }
    }

    func select(_ index: Int, palette: Palette) {
        withoutAnimation {
            selection.frame = itemFrame(index)
            selection.backgroundColor = palette.stripSelection.cgColor
        }
    }

    /// The strip item under an x in the keyboard view's coordinates, clamped to the ends.
    func stripIndex(at x: CGFloat) -> Int {
        let index = Int(floor((x - strip.frame.minX - Self.stripPadding) / stripItemWidth))
        return min(max(index, 0), stripItems.count - 1)
    }

    private func itemFrame(_ index: Int) -> CGRect {
        CGRect(x: Self.stripPadding + CGFloat(index) * stripItemWidth, y: Self.stripPadding,
               width: stripItemWidth, height: strip.bounds.height - 2 * Self.stripPadding)
    }

    private func place(_ image: CGImage?, in layer: CALayer, center: CGPoint) {
        layer.contents = image
        layer.contentsScale = scale
        guard let image else { return }
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        layer.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
