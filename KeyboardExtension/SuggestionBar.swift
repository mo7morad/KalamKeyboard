import UIKit

/// SPEC 5.4 placeholder: three equal slots with Apple's dividers, or the Full Access banner.
/// Phase 5 fills the slots.
final class SuggestionBar: UIView {
    private let slots = (0..<3).map { _ in UILabel() }
    private let dividers = (0..<2).map { _ in UIView() }
    private let banner = UILabel()

    var palette = Palette.light {
        didSet {
            (slots + [banner]).forEach { $0.textColor = palette.barText }
            dividers.forEach { $0.backgroundColor = palette.barDivider }
        }
    }

    var hasFullAccess = true {
        didSet {
            banner.isHidden = hasFullAccess
            (slots + dividers).forEach { $0.isHidden = !hasFullAccess }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        slots.forEach {
            $0.font = KeyFont.bar
            $0.textAlignment = .center
            addSubview($0)
        }
        dividers.forEach { addSubview($0) }
        banner.text = "Turn on Full Access for learning, haptics and sounds"
        banner.font = .systemFont(ofSize: 13)
        banner.textAlignment = .center
        banner.adjustsFontSizeToFitWidth = true
        banner.isHidden = true
        addSubview(banner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Divider geometry from the captures: 1 pt wide, 10 pt in from the bar's top and bottom.
    override func layoutSubviews() {
        super.layoutSubviews()
        let slot = bounds.width / 3
        for (i, label) in slots.enumerated() { label.frame = CGRect(x: CGFloat(i) * slot, y: 0, width: slot, height: bounds.height) }
        for (i, divider) in dividers.enumerated() { divider.frame = CGRect(x: CGFloat(i + 1) * slot - 0.5, y: 10, width: 1, height: bounds.height - 20) }
        banner.frame = bounds.insetBy(dx: 12, dy: 0)
    }
}
