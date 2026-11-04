import KalamEngine
import UIKit

protocol KeyboardViewDelegate: AnyObject {
    /// Every key, on touch-down (feedback, shift, page, the first backspace).
    func keyDown(_ key: Layout.Key)
    /// Non-char keys on touch-up (space, return, lang). Not sent for a space drag.
    func keyUp(_ key: Layout.Key)
    /// A char key's text; `point` is the commit point in key units, nil for a long-press pick.
    func commit(_ text: String, at point: Point?)
    func backspaceRepeated(_ count: Int)
    /// A backspace swipe now `words` steps to the left (0 puts everything back).
    func backspaceSwiped(words: Int)
    /// A finger that went down on a page key typed a key of the new page.
    func pageSlideEnded()
    func hideKeyboard()
    func moveCursor(by offset: Int)
    /// SPEC 5.2: the trackpad's direction from the text at the cursor, nil to follow the layout.
    func trackpadIsRightToLeft() -> Bool?
}

/// The host's return key (SPEC 5.2): a title for non-default types, nil for the ⏎ icon.
struct ReturnKeyStyle: Equatable {
    var title: String?
    var prominent = false
    var enabled = true
}

/// One view with layer-drawn keys and raw touch handling (SPEC D1, 5.2). It covers the suggestion
/// bar too, so popups can rise over it, but only takes touches in the key area and, mid-typing, the bar's bottom edge.
final class KeyboardView: UIView {
    /// Apple's is 44. Some host apps get about 16 pt of extra system panel above Kalam's view and
    /// some don't, so the bar is sized for none: 30 was cramped there (device round 2).
    static let barHeight: CGFloat = 40
    static let height = barHeight + KeyGeometry.height
    /// How far the top row's touch area reaches up into the bar. Moe's top-row taps run right up
    /// to the bar, and taps landing in it were lost (device round 2 trace). Only mid-typing while
    /// the bar has something to tap (SPEC 5.2, `BarBand`).
    static let topRowReach: CGFloat = 12

    weak var delegate: KeyboardViewDelegate?

    var layout: Layout? { didSet { rebuild() } }
    var shift: ShiftState.Mode = .off { didSet { if shift != oldValue { refreshContents() } } }
    var returnKey = ReturnKeyStyle() { didSet { if returnKey != oldValue { refreshContents() } } }
    var palette = Palette.light { didSet { refreshColors() } }
    var showsHints = true
    /// Whether the bar shows a suggestion or the clip chip (set by the view controller).
    var barHasTappableContent = false

    private var geometry: KeyGeometry?
    private var builtWidth: CGFloat = 0
    private var caps: [String: CALayer] = [:]
    private var presses: [Press] = []
    private let glyphs = GlyphCache()
    private let popups = PopupLayers()
    /// The latest key touch-down, in touch timestamps (system uptime).
    private var lastKeyDown: TimeInterval?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        layer.addSublayer(popups.bubble)
        layer.addSublayer(popups.strip)
        registerForTraitChanges([UITraitDisplayScale.self]) { (self: Self, _) in self.rebuild() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let now = event?.timestamp ?? CACurrentMediaTime()
        let reach = BarBand.belongsToKeys(barTappable: barHasTappableContent, sinceKeyDown: lastKeyDown.map { now - $0 })
        return point.y >= Self.barHeight - (reach ? Self.topRowReach : 0) && super.point(inside: point, with: event)
    }

    /// The globe key's cap frame, for the system's input-mode button placed over it.
    var globeFrame: CGRect? { geometry?.frames.first { $0.key.kind == .globe }?.cap }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != builtWidth { rebuild() }
    }

    // MARK: Drawing

    private func rebuild() {
        caps.values.forEach { $0.removeFromSuperlayer() }
        caps = [:]
        builtWidth = bounds.width
        guard let layout, bounds.width > 0 else { geometry = nil; return }
        glyphs.scale = traitCollection.displayScale
        popups.scale = glyphs.scale
        let geometry = KeyGeometry(layout: layout, width: bounds.width, origin: CGPoint(x: 0, y: Self.barHeight))
        self.geometry = geometry
        for frame in geometry.frames {
            let cap = CALayer()
            cap.frame = frame.cap
            cap.cornerRadius = 7.7
            cap.cornerCurve = .continuous
            cap.addSublayer(CALayer())  // label
            cap.addSublayer(CALayer())  // hint or space mark
            cap.sublayers?.forEach { $0.contentsScale = glyphs.scale }
            layer.insertSublayer(cap, below: popups.bubble)
            caps[frame.key.id] = cap
        }
        refreshColors()
    }

    private func refreshColors() {
        for (id, cap) in caps { cap.backgroundColor = (isPressed(id) ? palette.keyPressed : palette.key).cgColor }
        refreshContents()
    }

    private func refreshContents() {
        guard let geometry else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for frame in geometry.frames {
            guard let cap = caps[frame.key.id], let sublayers = cap.sublayers else { continue }
            setContents(of: sublayers[0], in: cap.bounds, image: labelImage(frame.key), centeredAt: labelCenter(frame.key, in: cap.bounds))
            let corner = cornerImage(frame.key)
            setContents(of: sublayers[1], in: cap.bounds, image: corner, centeredAt: cornerCenter(frame.key, image: corner, in: cap.bounds))
        }
        CATransaction.commit()
    }

    private func setContents(of layer: CALayer, in bounds: CGRect, image: CGImage?, centeredAt center: CGPoint) {
        layer.contents = image
        guard let image else { return }
        let size = CGSize(width: CGFloat(image.width) / glyphs.scale, height: CGFloat(image.height) / glyphs.scale)
        layer.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    private var isUppercase: Bool { shift != .off && layout?.lang == .en }

    private func displayText(_ key: Layout.Key) -> String {
        isUppercase && key.kind == .char ? key.label.uppercased() : key.label
    }

    /// Punctuation that Apple draws on the text baseline, without case-sensitive forms.
    private static let baselinePunctuation: Set<String> = [".", ",", ":", ";", "،", "؛"]
    /// Of those, the ones Apple sets a point lower still.
    private static let lowPunctuation: Set<String> = [".", ",", "،"]

    /// Arabic letters and Eastern digits (not the Latin or symbol keys of the Arabic pages).
    private static func isArabicScript(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { !$0.isASCII } && text.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    }

    private func font(for key: Layout.Key, text: String) -> UIFont {
        let arabicScript = Self.isArabicScript(text)
        switch key.kind {
        case .char where text.unicodeScalars.first == "\u{25CC}": return KeyFont.tanween
        case .char where arabicScript: return KeyFont.arabic
        case .char where Self.baselinePunctuation.contains(text): return KeyFont.uppercase
        case .char:
            guard text.first?.isLetter == true else { return KeyFont.symbol }
            return text == text.lowercased() ? KeyFont.lowercase : KeyFont.uppercase
        case .page where key.output == "symbols": return KeyFont.symbolsPage
        case .page where layout?.id.hasSuffix("symbols") == true && key.output == "numbers": return arabicScript ? KeyFont.arabicNumbersPage : KeyFont.numbersPage
        default: return arabicScript ? KeyFont.arabicFunction : KeyFont.function
        }
    }

    private func labelImage(_ key: Layout.Key) -> CGImage? {
        let isAR = layout?.lang == .ar
        switch key.kind {
        case .shift:
            let name = shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift"
            return glyphs.symbol(name, size: KeyFont.iconSize, color: palette.label)
        case .backspace: return glyphs.symbol("delete.left", size: KeyFont.iconSize, color: palette.label)
        case .globe: return glyphs.symbol("globe", size: KeyFont.iconSize, color: palette.label)
        case .space, .gap: return nil
        case .return:
            let color = returnKey.prominent ? UIColor.white : returnKey.enabled ? palette.label : palette.secondaryLabel
            guard let title = returnKey.title else { return glyphs.symbol(isAR ? "return.right" : "return.left", size: KeyFont.iconSize, color: color) }
            return glyphs.text(title, font: KeyFont.function, color: color)
        default:
            let text = displayText(key)
            return glyphs.text(text, font: font(for: key, text: text), color: palette.label)
        }
    }

    /// Vertical nudges from the captures: lowercase letters sit higher than the line box centers
    /// them; the shift, delete and Arabic return icons and the #+= page's 123 label sit lower.
    private func labelCenter(_ key: Layout.Key, in bounds: CGRect) -> CGPoint {
        let lowercase = key.kind == .char && layout?.lang == .en && !isUppercase && key.label.first?.isLetter == true
        let offset: CGFloat = switch key.kind {
        case .shift, .backspace: 0.5
        case .return where layout?.lang == .ar && returnKey.title == nil: 0.7
        case .page where layout?.id.hasSuffix("symbols") == true && key.output == "numbers": 0.3
        case .char where lowercase: -2.5
        case .char where Self.lowPunctuation.contains(key.label): 1
        case .char where Self.isArabicScript(key.label) || Self.baselinePunctuation.contains(key.label): 0
        default: -1
        }
        return CGPoint(x: bounds.midX, y: bounds.midY + offset)
    }

    private func cornerImage(_ key: Layout.Key) -> CGImage? {
        if key.kind == .space { return glyphs.text(layout?.lang == .ar ? "ع" : "A", font: KeyFont.spaceMark, color: palette.secondaryLabel) }
        guard drawsHint(key), let hint = key.hint else { return nil }
        return glyphs.text(hint, font: KeyFont.hint, color: palette.secondaryLabel)
    }

    /// Not on Arabic, like Apple: the corner digit sat on the letters' dots (ف غ خ ث ق).
    private func drawsHint(_ key: Layout.Key) -> Bool { showsHints && layout?.lang != .ar && key.hint != nil }

    private func cornerCenter(_ key: Layout.Key, image: CGImage?, in bounds: CGRect) -> CGPoint {
        guard let image else { return .zero }
        let size = CGSize(width: CGFloat(image.width) / glyphs.scale, height: CGFloat(image.height) / glyphs.scale)
        let bottom = key.kind == .space
        return CGPoint(x: bounds.maxX - (bottom ? 5 : 4) - size.width / 2,
                       y: bottom ? bounds.maxY - 2 - size.height / 2 : 2 + size.height / 2)
    }

    private func isPressed(_ id: String) -> Bool { presses.contains { $0.frame.key.id == id } }

    private func setPressed(_ frame: KeyGeometry.Frame, _ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caps[frame.key.id]?.backgroundColor = (pressed ? palette.keyPressed : palette.key).cgColor
        CATransaction.commit()
    }

    private func setLabelsHidden(_ hidden: Bool) {
        caps.values.forEach { $0.sublayers?.forEach { $0.isHidden = hidden } }
    }

    // MARK: Touches

    /// One finger on a key.
    private final class Press {
        let touch: UITouch
        var frame: KeyGeometry.Frame
        /// The kind of key it went down on; a shift or page press may slide onto a char key.
        let origin: Layout.Key.Kind
        let start: CGPoint
        let startTime: TimeInterval
        var timer: Timer?
        var strip: [String]?
        var selected = 0
        var trackpad: Trackpad?
        var repeats = 0
        var swipeWords: Int?

        init(touch: UITouch, frame: KeyGeometry.Frame, start: CGPoint) {
            (self.touch, self.frame, self.start) = (touch, frame, start)
            (origin, startTime) = (frame.key.kind, touch.timestamp)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            // SPEC 5.2 rollover: a new touch releases any letter, space or return still waiting for
            // its touch-up, so two thumbs keep their order ("hi there", not "hit here").
            for press in presses where rollsOver(press) {
                trace("rollover \(press.frame.key.id)")
                release(press)
            }
            let point = touch.location(in: self)
            guard let frame = geometry?.key(at: point) else { continue }
            traceTouch("began", touch, key: frame.key)
            let press = Press(touch: touch, frame: frame, start: point)
            lastKeyDown = touch.timestamp
            presses.append(press)
            setPressed(frame, true)
            delegate?.keyDown(frame.key)
            begin(press)
        }
    }

    private func begin(_ press: Press) {
        let key = press.frame.key
        switch key.kind {
        case .char:
            if key.popup { popups.showBubble(over: press.frame.cap, image: bubbleImage(key, text: displayText(key)), palette: palette) }
            scheduleLongPress(press)
        case .backspace:
            press.timer = after(BackspaceRepeat.delay) { [weak self, weak press] in
                guard let press else { return }
                press.timer = Timer.scheduledTimer(withTimeInterval: BackspaceRepeat.interval, repeats: true) { [weak self, weak press] _ in
                    guard let press else { return }
                    self?.delegate?.backspaceRepeated(press.repeats)
                    press.repeats += 1
                }
            }
        case .space:
            press.timer = after(0.4) { [weak self, weak press] in
                guard let press else { return }
                self?.startTrackpad(press)
            }
        default: break
        }
    }

    private func scheduleLongPress(_ press: Press) {
        press.timer?.invalidate()
        let key = press.frame.key
        guard let strip = longPressStrip(output: key.output, hint: key.hint, alternates: key.alternates, hintShown: drawsHint(key))
        else { return }
        press.timer = after(0.35) { [weak self, weak press] in
            guard let self, let press else { return }
            press.strip = strip.items.map { self.isUppercase ? $0.uppercased() : $0 }
            press.selected = strip.selected
            self.popups.hideBubble()
            self.popups.showStrip(items: press.strip ?? [], selected: press.selected, over: press.frame.cap,
                                  in: self.bounds, glyph: { self.stripImage($0) }, palette: self.palette)
        }
    }

    private func after(_ delay: TimeInterval, _ action: @escaping () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in action() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses.first(where: { $0.touch === touch }) else { continue }
            let point = touch.location(in: self)
            switch press.frame.key.kind {
            case .char where press.strip != nil:
                press.selected = popups.stripIndex(at: point.x)
                popups.select(press.selected, palette: palette)
            case .char:
                if !hidesOnSwipeDown(press, at: point) { slide(press, to: point) }
            case .shift, .page:
                slide(press, to: point)
            case .backspace:
                swipeBackspace(press, to: point)
            case .space:
                if press.trackpad == nil, abs(point.x - press.start.x) > Trackpad.startDistance { startTrackpad(press) }
                if var pad = press.trackpad {
                    let offset = pad.offset(toX: Double(point.x))
                    press.trackpad = pad
                    if offset != 0 { delegate?.moveCursor(by: offset) }
                }
            default: break
            }
        }
    }

    /// SPEC 5.2: the finger may slide; the popup follows it to the char key under it. A finger
    /// from shift or a page key becomes a char press this way.
    private func slide(_ press: Press, to point: CGPoint) {
        guard let frame = geometry?.key(at: point), frame.key.kind == .char, frame.key.id != press.frame.key.id else { return }
        trace("slide \(press.frame.key.id) -> \(frame.key.id)")
        setPressed(press.frame, false)
        press.frame = frame
        setPressed(frame, true)
        let text = press.origin == .shift ? frame.key.label.uppercased() : displayText(frame.key)  // shift may be off by now
        let image = bubbleImage(frame.key, text: text)
        if frame.key.popup { popups.showBubble(over: frame.cap, image: image, palette: palette) } else { popups.hideBubble() }
        scheduleLongPress(press)
    }

    /// SPEC 5.2 swipe down to hide: the letter isn't typed.
    private func hidesOnSwipeDown(_ press: Press, at point: CGPoint) -> Bool {
        guard press.origin == .char, let geometry,
              SwipeDownHide.triggers(startRow: Int(geometry.keyUnits(press.start).y), dx: Double(point.x - press.start.x),
                                     dy: Double(point.y - press.start.y), elapsed: press.touch.timestamp - press.startTime)
        else { return false }
        trace("swipe down from \(press.frame.key.id)")
        finish(press)
        delegate?.hideKeyboard()
        return true
    }

    /// SPEC 5.2 backspace swipe: past the start distance the repeat stops and whole words go, live.
    private func swipeBackspace(_ press: Press, to point: CGPoint) {
        let dx = Double(press.start.x - point.x)
        if press.swipeWords == nil {
            guard dx > BackspaceSwipe.startDistance else { return }
            press.timer?.invalidate()
            trace("backspace swipe")
        }
        let words = BackspaceSwipe.words(left: dx)
        guard words != press.swipeWords else { return }
        press.swipeWords = words
        delegate?.backspaceSwiped(words: words)
    }

    private func startTrackpad(_ press: Press) {
        press.timer?.invalidate()
        guard press.trackpad == nil else { return }
        let rightToLeft = delegate?.trackpadIsRightToLeft() ?? (layout?.lang == .ar)
        press.trackpad = Trackpad(startX: Double(press.touch.location(in: self).x), downX: Double(press.start.x), rightToLeft: rightToLeft)
        setLabelsHidden(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let press = presses.first(where: { $0.touch === touch }) else { continue }
            traceTouch("ended", touch, key: press.frame.key)
            release(press)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses.first(where: { $0.touch === touch }) else { continue }
            traceTouch("cancelled", touch, key: press.frame.key)
            // SPEC 5.2: a system cancel (edge gesture, banner) still types a letter that was really pressed.
            let held = CACurrentMediaTime() - press.startTime
            if CancelledTouch.commits(isChar: press.frame.key.kind == .char, stripOpen: press.strip != nil, heldFor: held) {
                release(press)
            } else {
                finish(press)
            }
        }
    }

    private func rollsOver(_ press: Press) -> Bool {
        switch press.frame.key.kind {
        case .char: press.strip == nil
        case .space: press.trackpad == nil
        case .return: true
        default: false
        }
    }

    /// The touch-up action: a char commits, other keys send keyUp (not a space drag, nor the keys
    /// that act on touch-down). A still space hold is a slow tap (SPEC 5.2).
    private func release(_ press: Press) {
        switch press.frame.key.kind {
        case .char:
            commit(press)
            if press.origin == .page { delegate?.pageSlideEnded() }
        case .space where press.trackpad?.releaseTypesSpace == false: break
        case .backspace, .shift, .page, .gap, .globe: break
        default:
            trace("keyUp \(press.frame.key.kind)")
            delegate?.keyUp(press.frame.key)
        }
        finish(press)
    }

    private func commit(_ press: Press) {
        let picked = press.strip.map { $0[press.selected] } ?? press.frame.key.output
        let text = press.origin == .shift ? picked.uppercased() : picked  // shift may be off by now
        let point = press.strip == nil ? geometry?.keyUnits(press.touch.location(in: self)) : nil
        trace("commit \(text.debugDescription)")
        delegate?.commit(text, at: point)
    }

    private func traceTouch(_ phase: String, _ touch: UITouch, key: Layout.Key) {
        trace({
            let units = geometry?.keyUnits(touch.location(in: self)) ?? Point(x: -1, y: -1)
            return String(format: "touch %@ %@ at %.2f,%.2f lag %.1f ms", phase, key.id, units.x, units.y,
                          (CACurrentMediaTime() - touch.timestamp) * 1000)
        }())
    }

    private func finish(_ press: Press) {
        press.timer?.invalidate()
        presses.removeAll { $0 === press }
        setPressed(press.frame, isPressed(press.frame.key.id))
        if press.trackpad != nil { setLabelsHidden(false) }
        if press.frame.key.kind == .char {
            popups.hideBubble()
            if press.strip != nil { popups.hideStrip() }
        }
    }

    private func bubbleImage(_ key: Layout.Key, text: String) -> CGImage? {
        let base = font(for: key, text: text)
        return glyphs.text(text, font: base.withSize(base.pointSize * 1.35), color: palette.label)
    }

    /// Combining marks (the tashkeel strip) sit on a dotted circle, like the tanween key's own label.
    private func stripImage(_ text: String) -> CGImage? {
        if text.unicodeScalars.first?.properties.generalCategory == .nonspacingMark {
            return glyphs.text("\u{25CC}" + text, font: KeyFont.tanween, color: palette.label)
        }
        return glyphs.text(text, font: layout?.lang == .ar ? KeyFont.arabic : KeyFont.uppercase, color: palette.label)
    }
}
