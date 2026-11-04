import KalamEngine
import UIKit

/// SPEC 5.6: the emoji panel in place of the keys, drawn with Apple's emoji font. A horizontally
/// scrolling grid of 5 rows (Recents, then Apple's categories) over a strip with ABC, one icon per
/// category (a tap jumps there; the current one is highlighted) and backspace. Cells are reused
/// labels, so only the visible emoji are ever drawn (the extension is killed near 60 MB).
final class EmojiPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onEmoji: ((String) -> Void)?
    var onABC: (() -> Void)?
    var onBackspace: (() -> Void)?
    /// A held backspace's repeat number, from 0 (BackspaceRepeat's timing, as on the keys).
    var onBackspaceRepeat: ((Int) -> Void)?

    var palette = Palette.light {
        didSet { applyPalette() }
    }

    private struct Section {
        let name: String
        let symbol: String
        var emoji: [String]
    }

    private var sections: [Section]
    private var current = 0
    private let title = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let abcButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .custom)
    private var categoryButtons: [UIButton] = []
    private var repeatTimer: Timer?

    private static let rows: CGFloat = 5
    private static let titleHeight: CGFloat = 24
    private static let stripHeight: CGFloat = 40
    private static let gap: CGFloat = 8
    private static let recentsKey = "emojiRecents"
    private static let symbols = [
        "Smileys & People": "face.smiling", "Animals & Nature": "teddybear", "Food & Drink": "fork.knife",
        "Activity": "basketball", "Travel & Places": "car", "Objects": "lightbulb", "Symbols": "heart", "Flags": "flag",
    ]

    /// Recents live in App Group defaults; without Full Access they may not persist, which is fine.
    private static var defaults: UserDefaults { UserDefaults(suiteName: Settings.appGroup) ?? .standard }

    override init(frame: CGRect) {
        sections = [Section(name: "Recents", symbol: "clock", emoji: [])]
            + EmojiIndex.shared.categories.map { Section(name: $0.name, symbol: Self.symbols[$0.name] ?? "circle", emoji: $0.emoji) }
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: Self.gap, bottom: 0, right: Self.gap)
        grid.backgroundColor = .clear
        grid.showsHorizontalScrollIndicator = false
        if #available(iOS 26, *) { grid.topEdgeEffect.isHidden = true }
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = KeyFont.bar
        abcButton.addTarget(self, action: #selector(abcTapped), for: .touchUpInside)
        let glyph = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        backspaceButton.setImage(UIImage(systemName: "delete.left", withConfiguration: glyph), for: .normal)
        backspaceButton.accessibilityLabel = "Delete"
        backspaceButton.addTarget(self, action: #selector(backspaceDown), for: .touchDown)
        backspaceButton.addTarget(self, action: #selector(backspaceUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        categoryButtons = sections.indices.map { index in
            let button = UIButton(type: .custom)
            button.setImage(UIImage(systemName: sections[index].symbol, withConfiguration: glyph), for: .normal)
            button.accessibilityLabel = sections[index].name
            button.layer.cornerRadius = 14
            button.tag = index
            button.addTarget(self, action: #selector(categoryTapped), for: .touchUpInside)
            return button
        }
        ([grid, title, abcButton, backspaceButton] + categoryButtons).forEach { addSubview($0) }
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// On open: the latest recents, starting at Recents (or the first category when there are none).
    func reload() {
        sections[0].emoji = Self.defaults.stringArray(forKey: Self.recentsKey) ?? []
        grid.reloadData()
        grid.layoutIfNeeded()
        grid.contentOffset = .zero
        updateCurrent()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gridHeight = bounds.height - Self.titleHeight - Self.stripHeight
        title.frame = CGRect(x: 2 * Self.gap, y: 0, width: bounds.width - 4 * Self.gap, height: Self.titleHeight)
        grid.frame = CGRect(x: 0, y: Self.titleHeight, width: bounds.width, height: gridHeight)
        let row = floor(gridHeight / Self.rows)
        if layout.itemSize.height != row {
            layout.itemSize = CGSize(width: floor(row * 1.15), height: row)
            EmojiCell.font = .systemFont(ofSize: floor(row * 0.8))
            grid.reloadData()
        }
        let stripY = bounds.height - Self.stripHeight
        abcButton.frame = CGRect(x: 4, y: stripY, width: 52, height: Self.stripHeight)
        backspaceButton.frame = CGRect(x: bounds.width - 56, y: stripY, width: 52, height: Self.stripHeight)
        let start = abcButton.frame.maxX, width = (backspaceButton.frame.minX - start) / CGFloat(categoryButtons.count)
        for (i, button) in categoryButtons.enumerated() {
            let cell = CGRect(x: start + CGFloat(i) * width, y: stripY, width: width, height: Self.stripHeight)
            button.frame = CGRect(x: cell.midX - 14, y: cell.midY - 14, width: 28, height: 28)
        }
    }

    private func applyPalette() {
        title.textColor = palette.secondaryLabel
        abcButton.setTitleColor(palette.barText, for: .normal)
        backspaceButton.tintColor = palette.barText
        highlightCurrent()
        grid.reloadData()
    }

    // MARK: Grid

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].emoji.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.id, for: indexPath) as! EmojiCell
        cell.show(sections[indexPath.section].emoji[indexPath.item], pressed: palette.keyPressed)
        return cell
    }

    /// Inserts it and makes it the newest recent. The Recents section itself waits for the next
    /// open, so the grid doesn't shift under Moe's finger.
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        let emoji = sections[indexPath.section].emoji[indexPath.item]
        onEmoji?(emoji)
        Self.defaults.set(addingRecent(emoji, to: Self.defaults.stringArray(forKey: Self.recentsKey) ?? []), forKey: Self.recentsKey)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateCurrent() }

    /// The current category is the one at the grid's left edge.
    private func updateCurrent() {
        let section = grid.indexPathsForVisibleItems.min()?.section ?? (sections[0].emoji.isEmpty ? 1 : 0)
        guard section != current || title.text == nil else { return }
        current = section
        title.text = sections[section].name.uppercased()
        highlightCurrent()
    }

    private func highlightCurrent() {
        for (i, button) in categoryButtons.enumerated() {
            button.tintColor = i == current ? palette.label : palette.secondaryLabel
            button.backgroundColor = i == current ? palette.stripSelection : nil
        }
    }

    // MARK: Strip

    @objc private func categoryTapped(_ button: UIButton) {
        if sections[button.tag].emoji.isEmpty {
            grid.contentOffset = .zero  // only Recents can be empty, and it comes first
        } else {
            grid.scrollToItem(at: IndexPath(item: 0, section: button.tag), at: .left, animated: false)
        }
        updateCurrent()
    }

    @objc private func abcTapped() { onABC?() }

    @objc private func backspaceDown() {
        onBackspace?()
        scheduleRepeat(0, after: BackspaceRepeat.delay)
    }

    /// SPEC 5.2: one-shot timers, each waiting the next repeat's interval, as on the keys.
    private func scheduleRepeat(_ n: Int, after delay: TimeInterval) {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.onBackspaceRepeat?(n)
            self?.scheduleRepeat(n + 1, after: BackspaceRepeat.interval(afterRepeat: n))
        }
    }

    @objc private func backspaceUp() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// One emoji: a reused label in Apple's emoji font.
private final class EmojiCell: UICollectionViewCell {
    static let id = "emoji"
    static var font = UIFont.systemFont(ofSize: 30)
    private let label = UILabel()
    private var pressed = UIColor.clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true  // a few glyphs (saluting face) are wider than the cell
        label.minimumScaleFactor = 0.7
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? pressed : nil }
    }

    func show(_ emoji: String, pressed: UIColor) {
        label.text = emoji
        label.font = Self.font
        self.pressed = pressed
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}
