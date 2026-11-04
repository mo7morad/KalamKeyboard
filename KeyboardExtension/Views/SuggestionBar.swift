import KalamEngine
import UIKit

/// SPEC 5.4: three slots with Apple's dividers, or the Full Access banner. A tap picks a slot; a
/// long-press offers "Don't suggest ‘x’" in place of the slots (extensions can't show alerts).
/// SPEC 5.5 adds the clipboard button at the left edge and the clip chip in the primary slot;
/// while the clipboard panel is open, the bar is its header: "Clipboard", "Clear" and "ABC".
/// SPEC 5.6 adds the emoji button right of it, shown always; the emoji panel hides the slots.
/// SPEC 5.2: touch-down on a slot with something in it highlights it like a key and plays the key
/// feedback (`onPress`); the pick still fires on release.
final class SuggestionBar: UIView {
    var onPick: ((BarSlot) -> Void)?
    var onBlock: ((BarSlot) -> Void)?
    var onClipboard: (() -> Void)?
    var onEmoji: (() -> Void)?
    var onChip: (() -> Void)?
    var onClear: (() -> Void)?
    var onClose: (() -> Void)?
    /// Touch-down on a slot or the clip chip, for the key haptic and click.
    var onPress: (() -> Void)?

    private let labels = (0..<3).map { _ in UILabel() }
    private let dividers = (0..<2).map { _ in UIView() }
    private let banner = UILabel()
    private let blockButton = UIButton(type: .system)
    private let clipboardButton = UIButton(type: .custom)
    private let emojiButton = UIButton(type: .custom)
    private let panelTitle = UILabel()
    private let clearButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var blocking: BarSlot?
    private var pressed: UILabel?

    private static let primary = 1
    private static let buttonWidth: CGFloat = 44

    /// Visual left to right; nil is an empty slot.
    var slots: [BarSlot?] = [nil, nil, nil] {
        didSet {
            hideBlock()
            render()
        }
    }

    /// The clip the primary slot offers instead of its suggestion, shown by its first line.
    var chip: String? {
        didSet { render() }
    }

    /// Whether a tap at `point` would pick something: a suggestion, the clip chip, or the "Don't
    /// suggest" overlay (SPEC 5.2: only there does the top row's reach into the bar give way).
    func hasTarget(at point: CGPoint) -> Bool { blocking != nil || pickableSlot(at: point) != nil }

    var showsClipboardButton = false {
        didSet {
            clipboardButton.isHidden = !showsClipboardButton
            setNeedsLayout()
        }
    }

    /// While the panel is open the slots give way to its header, and the button shows as selected.
    var isPanelOpen = false {
        didSet {
            hideBlock()
            [panelTitle, clearButton, closeButton].forEach { $0.isHidden = !isPanelOpen }
            clipboardButton.backgroundColor = isPanelOpen ? palette.key : nil
            showSlots()
        }
    }

    var isEmojiOpen = false {
        didSet {
            hideBlock()
            emojiButton.backgroundColor = isEmojiOpen ? palette.key : nil
            showSlots()
        }
    }

    var palette = Palette.light {
        didSet {
            (labels + [banner]).forEach { $0.textColor = palette.barText }
            blockButton.setTitleColor(palette.barText, for: .normal)
            clipboardButton.tintColor = palette.barText
            emojiButton.tintColor = palette.barText
            emojiButton.backgroundColor = isEmojiOpen ? palette.key : nil
            clipboardButton.backgroundColor = isPanelOpen ? palette.key : nil
            panelTitle.textColor = palette.barText
            [clearButton, closeButton].forEach { $0.setTitleColor(palette.barText, for: .normal) }
            dividers.forEach { $0.backgroundColor = palette.barDivider }
        }
    }

    var hasFullAccess = true {
        didSet {
            banner.isHidden = hasFullAccess
            hideBlock()
            showSlots()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        labels.forEach {
            $0.font = KeyFont.bar
            $0.textAlignment = .center
            $0.lineBreakMode = .byTruncatingMiddle
            $0.layer.cornerRadius = 8
            $0.layer.cornerCurve = .continuous
            addSubview($0)
        }
        dividers.forEach { addSubview($0) }
        banner.text = "Turn on Full Access for learning, haptics and sounds"
        banner.font = .systemFont(ofSize: 13)
        banner.textAlignment = .center
        banner.adjustsFontSizeToFitWidth = true
        banner.isHidden = true
        addSubview(banner)
        blockButton.titleLabel?.font = KeyFont.bar
        blockButton.isHidden = true
        blockButton.addTarget(self, action: #selector(blockTapped), for: .touchUpInside)
        addSubview(blockButton)
        // A toolbar glyph at the bar text's size and weight, not a key.
        let glyph = UIImage.SymbolConfiguration(font: KeyFont.bar, scale: .default)
        clipboardButton.setImage(UIImage(systemName: "clipboard", withConfiguration: glyph), for: .normal)
        clipboardButton.layer.cornerRadius = 8
        clipboardButton.accessibilityLabel = "Clipboard"
        clipboardButton.isHidden = true
        clipboardButton.addTarget(self, action: #selector(clipboardTapped), for: .touchUpInside)
        emojiButton.setImage(UIImage(systemName: "face.smiling", withConfiguration: glyph), for: .normal)
        emojiButton.layer.cornerRadius = 8
        emojiButton.accessibilityLabel = "Emoji"
        emojiButton.addTarget(self, action: #selector(emojiTapped), for: .touchUpInside)
        addSubview(emojiButton)
        panelTitle.text = "Clipboard"
        panelTitle.font = KeyFont.barBold
        for (button, name, action) in [(clearButton, "Clear", #selector(clearTapped)), (closeButton, "ABC", #selector(closeTapped))] {
            button.setTitle(name, for: .normal)
            button.titleLabel?.font = KeyFont.bar
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        for view in [clipboardButton, panelTitle, clearButton, closeButton] {
            view.isHidden = true
            addSubview(view)
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Divider geometry from the captures: 1 pt wide and 24 pt tall, centered in the bar.
    /// The slots share the width right of the clipboard (when it shows) and emoji buttons.
    private var slotsStart: CGFloat { (showsClipboardButton ? 2 : 1) * Self.buttonWidth }
    private var slotWidth: CGFloat { (bounds.width - slotsStart) / 3 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let start = slotsStart, slot = slotWidth
        for (i, label) in labels.enumerated() { label.frame = CGRect(x: start + CGFloat(i) * slot + 4, y: 0, width: slot - 8, height: bounds.height) }
        for (i, divider) in dividers.enumerated() { divider.frame = CGRect(x: start + CGFloat(i + 1) * slot - 0.5, y: bounds.midY - 12, width: 1, height: 24) }
        clipboardButton.frame = CGRect(x: 4, y: 6, width: Self.buttonWidth - 8, height: bounds.height - 12)
        emojiButton.frame = CGRect(x: slotsStart - Self.buttonWidth + 4, y: 6, width: Self.buttonWidth - 8, height: bounds.height - 12)
        panelTitle.frame = CGRect(x: start + 6, y: 0, width: 120, height: bounds.height)
        closeButton.frame = CGRect(x: bounds.width - 60, y: 0, width: 56, height: bounds.height)
        clearButton.frame = CGRect(x: closeButton.frame.minX - 60, y: 0, width: 60, height: bounds.height)
        banner.frame = CGRect(x: start + 8, y: 0, width: bounds.width - start - 20, height: bounds.height)
        blockButton.frame = bounds
    }

    private func render() {
        for (i, (label, slot)) in zip(labels, slots).enumerated() {
            if i == Self.primary, let chip {
                label.text = "\u{1F4CB} " + (chip.split(whereSeparator: \.isNewline).first.map(String.init) ?? chip)
                label.font = KeyFont.bar
                label.lineBreakMode = .byTruncatingTail
            } else {
                label.text = slot?.label
                label.font = slot?.bold == true ? KeyFont.barBold : KeyFont.bar
                label.lineBreakMode = .byTruncatingMiddle
            }
        }
    }

    /// The slot index at `point`, if the slots are showing.
    private func slotIndex(at point: CGPoint) -> Int? {
        guard hasFullAccess, !isPanelOpen, !isEmojiOpen, slotWidth > 0 else { return nil }
        let x = point.x - slotsStart
        let index = x < 0 ? -1 : Int(x / slotWidth)
        return slots.indices.contains(index) ? index : nil
    }

    /// The slot at `point` with something to pick in it (a suggestion, or the clip chip).
    private func pickableSlot(at point: CGPoint) -> Int? {
        guard let index = slotIndex(at: point), slots[index] != nil || (index == Self.primary && chip != nil) else { return nil }
        return index
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        if blocking != nil { return hideBlock() }
        guard let index = slotIndex(at: gesture.location(in: self)) else { return }
        if index == Self.primary, chip != nil {
            onChip?()
        } else if let slot = slots[index] {
            onPick?(slot)
        }
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let index = slotIndex(at: gesture.location(in: self)), !(index == Self.primary && chip != nil),
              let slot = slots[index], !slot.isLiteral, !slot.isEmoji else { return }
        blocking = slot
        blockButton.setTitle("Don\u{2019}t suggest \u{2018}\(slot.word)\u{2019}", for: .normal)
        blockButton.isHidden = false
        showSlots()
    }

    // MARK: Press feedback (the recognizers above still pick on release)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let point = touches.first?.location(in: self) else { return }
        let index = blocking == nil ? pickableSlot(at: point) : nil
        trace(String(format: "bar touch at %.1f,%.1f slot %@", Double(point.x), Double(point.y), index.map(String.init) ?? "none"))
        guard let index else { return }
        setPressed(labels[index])
        onPress?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        setPressed(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        setPressed(nil)
    }

    private func setPressed(_ label: UILabel?) {
        pressed?.layer.backgroundColor = nil
        pressed = label
        label?.layer.backgroundColor = palette.keyPressed.cgColor
    }

    @objc private func clipboardTapped() { onClipboard?() }
    @objc private func emojiTapped() { onEmoji?() }
    @objc private func clearTapped() { onClear?() }
    @objc private func closeTapped() { onClose?() }

    @objc private func blockTapped() {
        if let blocking { onBlock?(blocking) }
        hideBlock()
    }

    private func hideBlock() {
        guard blocking != nil else { return }
        blocking = nil
        blockButton.isHidden = true
        showSlots()
    }

    private func showSlots() {
        (labels + dividers).forEach { $0.isHidden = !hasFullAccess || isPanelOpen || isEmojiOpen || blocking != nil }
    }
}
