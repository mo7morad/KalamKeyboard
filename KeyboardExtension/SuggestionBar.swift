import KalamEngine
import UIKit

/// SPEC 5.4: three slots with Apple's dividers, or the Full Access banner. A tap picks a slot; a
/// long-press offers "Don't suggest ‘x’" in place of the slots (extensions can't show alerts).
final class SuggestionBar: UIView {
    var onPick: ((BarSlot) -> Void)?
    var onBlock: ((BarSlot) -> Void)?

    private let labels = (0..<3).map { _ in UILabel() }
    private let dividers = (0..<2).map { _ in UIView() }
    private let banner = UILabel()
    private let blockButton = UIButton(type: .system)
    private var blocking: BarSlot?

    /// Visual left to right; nil is an empty slot.
    var slots: [BarSlot?] = [nil, nil, nil] {
        didSet {
            hideBlock()
            for (label, slot) in zip(labels, slots) {
                label.text = slot?.label
                label.font = slot?.bold == true ? KeyFont.barBold : KeyFont.bar
            }
        }
    }

    var palette = Palette.light {
        didSet {
            (labels + [banner]).forEach { $0.textColor = palette.barText }
            blockButton.setTitleColor(palette.barText, for: .normal)
            dividers.forEach { $0.backgroundColor = palette.barDivider }
        }
    }

    var hasFullAccess = true {
        didSet {
            banner.isHidden = hasFullAccess
            (labels + dividers).forEach { $0.isHidden = !hasFullAccess }
            hideBlock()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        labels.forEach {
            $0.font = KeyFont.bar
            $0.textAlignment = .center
            $0.lineBreakMode = .byTruncatingMiddle
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
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Divider geometry from the captures: 1 pt wide, 10 pt in from the bar's top and bottom.
    override func layoutSubviews() {
        super.layoutSubviews()
        let slot = bounds.width / 3
        for (i, label) in labels.enumerated() { label.frame = CGRect(x: CGFloat(i) * slot + 4, y: 0, width: slot - 8, height: bounds.height) }
        for (i, divider) in dividers.enumerated() { divider.frame = CGRect(x: CGFloat(i + 1) * slot - 0.5, y: 10, width: 1, height: bounds.height - 20) }
        banner.frame = bounds.insetBy(dx: 12, dy: 0)
        blockButton.frame = bounds
    }

    private func slot(at gesture: UIGestureRecognizer) -> BarSlot? {
        guard hasFullAccess, bounds.width > 0 else { return nil }
        let index = Int(gesture.location(in: self).x / (bounds.width / 3))
        return slots.indices.contains(index) ? slots[index] : nil
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        if blocking != nil { return hideBlock() }
        if let slot = slot(at: gesture) { onPick?(slot) }
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let slot = slot(at: gesture), !slot.isLiteral else { return }
        blocking = slot
        blockButton.setTitle("Don\u{2019}t suggest \u{2018}\(slot.word)\u{2019}", for: .normal)
        blockButton.isHidden = false
        (labels + dividers).forEach { $0.isHidden = true }
    }

    @objc private func blockTapped() {
        if let blocking { onBlock?(blocking) }
        hideBlock()
    }

    private func hideBlock() {
        guard blocking != nil else { return }
        blocking = nil
        blockButton.isHidden = true
        (labels + dividers).forEach { $0.isHidden = !hasFullAccess }
    }
}
