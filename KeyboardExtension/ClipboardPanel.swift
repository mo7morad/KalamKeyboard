import KalamEngine
import UIKit

/// SPEC 5.5: the clipboard panel in place of the keys (its header is the suggestion bar): a
/// two-column grid of 3-line tiles. A tap pastes; a long-press turns the tile into
/// Pin/Unpin and Delete buttons (extensions can't show menus or alerts reliably).
final class ClipboardPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onPaste: ((String) -> Void)?
    var onPin: ((String, Bool) -> Void)?
    var onDelete: ((String) -> Void)?

    /// In panel order.
    var items: [ClipboardHistory.Item] = [] {
        didSet {
            if !items.contains(where: { $0.text == actionsFor }) { actionsFor = nil }
            empty.isHidden = !items.isEmpty
            grid.reloadData()
        }
    }

    var palette = Palette.light {
        didSet {
            empty.textColor = palette.secondaryLabel
            grid.reloadData()
        }
    }

    /// The tile showing its Pin/Delete buttons.
    private var actionsFor: String?
    private let empty = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)

    private static let gap: CGFloat = 8
    private static let tileHeight: CGFloat = 72

    override init(frame: CGRect) {
        super.init(frame: frame)
        empty.text = "Text you copy shows up here. Pinned items stay; others go after an hour."
        empty.font = .systemFont(ofSize: 15)
        empty.numberOfLines = 0
        empty.textAlignment = .center
        layout.minimumInteritemSpacing = Self.gap
        layout.minimumLineSpacing = Self.gap
        layout.sectionInset = UIEdgeInsets(top: Self.gap, left: Self.gap, bottom: Self.gap, right: Self.gap)
        grid.backgroundColor = .clear
        grid.dataSource = self
        grid.delegate = self
        grid.register(ClipTile.self, forCellWithReuseIdentifier: ClipTile.id)
        grid.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed)))
        [grid, empty].forEach { addSubview($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        grid.frame = bounds
        empty.frame = bounds.insetBy(dx: 32, dy: 0)
        layout.itemSize = CGSize(width: floor((bounds.width - 3 * Self.gap) / 2), height: Self.tileHeight)
    }

    // MARK: Grid

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let tile = collectionView.dequeueReusableCell(withReuseIdentifier: ClipTile.id, for: indexPath) as! ClipTile
        let item = items[indexPath.item]
        tile.show(item, actions: item.text == actionsFor, palette: palette)
        tile.onPin = { [weak self] in self?.onPin?(item.text, !item.pinned) }
        tile.onDelete = { [weak self] in self?.onDelete?(item.text) }
        return tile
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if actionsFor != nil { return hideActions() }
        onPaste?(items[indexPath.item].text)
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let path = grid.indexPathForItem(at: gesture.location(in: grid)) else { return }
        actionsFor = items[path.item].text
        grid.reloadData()
    }

    private func hideActions() {
        actionsFor = nil
        grid.reloadData()
    }
}

/// One clip: up to 3 lines (right-aligned for Arabic) and a pin mark, or its two action buttons.
private final class ClipTile: UICollectionViewCell {
    static let id = "clip"
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?

    private let label = UILabel()
    private let pinMark = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let pinButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private var palette = Palette.light

    /// A long clip's tile only needs its start, and laying out 10,000 characters per tile is waste.
    private static let shownCharacters = 300

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 3
        label.lineBreakMode = .byTruncatingTail
        pinMark.contentMode = .scaleAspectFit
        for (button, action) in [(pinButton, #selector(pinTapped)), (deleteButton, #selector(deleteTapped))] {
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        deleteButton.setTitle("Delete", for: .normal)
        [label, pinMark, pinButton, deleteButton].forEach { contentView.addSubview($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? palette.keyPressed : palette.key }
    }

    func show(_ item: ClipboardHistory.Item, actions: Bool, palette: Palette) {
        self.palette = palette
        contentView.backgroundColor = palette.key
        label.text = String(item.text.prefix(Self.shownCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        label.textColor = palette.label
        label.textAlignment = isRightToLeft(item.text) ? .right : .left
        pinMark.tintColor = palette.secondaryLabel
        pinButton.setTitle(item.pinned ? "Unpin" : "Pin", for: .normal)
        [pinButton, deleteButton].forEach { $0.setTitleColor(palette.label, for: .normal) }
        label.isHidden = actions
        pinMark.isHidden = actions || !item.pinned
        pinButton.isHidden = !actions
        deleteButton.isHidden = !actions
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let text = bounds.insetBy(dx: 10, dy: 8)  // top-aligned, as a short clip would float otherwise
        label.frame = CGRect(origin: text.origin, size: CGSize(width: text.width, height: min(text.height, label.sizeThatFits(text.size).height)))
        pinMark.frame = CGRect(x: bounds.width - 14, y: 3, width: 10, height: 10)
        pinButton.frame = CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
        deleteButton.frame = pinButton.frame.offsetBy(dx: bounds.width / 2, dy: 0)
    }

    @objc private func pinTapped() { onPin?() }
    @objc private func deleteTapped() { onDelete?() }

    /// Whether the text starts in a right-to-left script (Hebrew, Arabic and their presentation forms).
    private func isRightToLeft(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first(where: \.properties.isAlphabetic) else { return false }
        return (0x0590...0x08FF).contains(first.value) || (0xFB1D...0xFEFC).contains(first.value)
    }
}
