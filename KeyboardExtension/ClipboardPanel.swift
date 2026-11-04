import KalamEngine
import UIKit

/// SPEC 5.5: the clipboard panel in place of the keys (its header is the suggestion bar): a
/// two-column grid of 3-line text tiles and image thumbnails. A tap pastes a text or copies an
/// image back to the pasteboard; a long-press turns the tile into Pin/Unpin and Delete buttons
/// (extensions can't show menus or alerts reliably).
final class ClipboardPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onPaste: ((String) -> Void)?
    /// Returns whether the image is on the pasteboard now.
    var onCopy: ((ClipboardHistory.Image) -> Bool)?
    var onPin: ((ClipboardHistory.Content, Bool) -> Void)?
    var onDelete: ((ClipboardHistory.Content) -> Void)?
    /// Where the image thumbnails are.
    var folder: URL?

    /// In panel order.
    var items: [ClipboardHistory.Item] = [] {
        didSet {
            if !items.contains(where: { $0.content == actionsFor }) { actionsFor = nil }
            empty.isHidden = !items.isEmpty
            grid.reloadData()
        }
    }

    var palette = Palette.light {
        didSet {
            empty.textColor = palette.secondaryLabel
            toast.backgroundColor = palette.label
            toast.textColor = palette.key
            grid.reloadData()
        }
    }

    /// The tile showing its Pin/Delete buttons.
    private var actionsFor: ClipboardHistory.Content?
    private let empty = UILabel()
    /// After an image tap: how to paste it, since the keyboard can't.
    private let toast = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)

    private static let gap: CGFloat = 8
    private static let tileHeight: CGFloat = 72

    override init(frame: CGRect) {
        super.init(frame: frame)
        empty.text = "Text and images you copy show up here. Pinned items stay; others go after an hour."
        empty.font = .systemFont(ofSize: 15)
        empty.numberOfLines = 0
        empty.textAlignment = .center
        toast.text = "Copied. Hold the text field and tap Paste."
        toast.font = .systemFont(ofSize: 15, weight: .medium)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.isHidden = true
        layout.minimumInteritemSpacing = Self.gap
        layout.minimumLineSpacing = Self.gap
        layout.sectionInset = UIEdgeInsets(top: Self.gap, left: Self.gap, bottom: Self.gap, right: Self.gap)
        grid.backgroundColor = .clear
        if #available(iOS 26, *) { grid.topEdgeEffect.isHidden = true }  // a light band under the header
        grid.dataSource = self
        grid.delegate = self
        grid.register(ClipTile.self, forCellWithReuseIdentifier: ClipTile.id)
        grid.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed)))
        [grid, empty, toast].forEach { addSubview($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        grid.frame = bounds
        empty.frame = bounds.insetBy(dx: 32, dy: 0)
        toast.frame = CGRect(x: Self.gap, y: bounds.height - 44 - Self.gap, width: bounds.width - 2 * Self.gap, height: 44)
        layout.itemSize = CGSize(width: floor((bounds.width - 3 * Self.gap) / 2), height: Self.tileHeight)
    }

    // MARK: Grid

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let tile = collectionView.dequeueReusableCell(withReuseIdentifier: ClipTile.id, for: indexPath) as! ClipTile
        let item = items[indexPath.item]
        tile.show(item, actions: item.content == actionsFor, folder: folder, palette: palette)
        tile.onPin = { [weak self] in self?.onPin?(item.content, !item.pinned) }
        tile.onDelete = { [weak self] in self?.onDelete?(item.content) }
        return tile
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if actionsFor != nil { return hideActions() }
        switch items[indexPath.item].content {
        case .text(let text): onPaste?(text)
        case .image(let image): if onCopy?(image) == true { showToast() }
        }
    }

    private func showToast() {
        toast.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideToast), object: nil)
        perform(#selector(hideToast), with: nil, afterDelay: 2)
    }

    @objc private func hideToast() { toast.isHidden = true }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let path = grid.indexPathForItem(at: gesture.location(in: grid)) else { return }
        actionsFor = items[path.item].content
        grid.reloadData()
    }

    private func hideActions() {
        actionsFor = nil
        grid.reloadData()
    }
}

/// One clip: up to 3 lines (right-aligned for Arabic) or an image's thumbnail, and a pin mark, or
/// its two action buttons.
private final class ClipTile: UICollectionViewCell {
    static let id = "clip"
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?

    private let label = UILabel()
    private let thumbnail = UIImageView()
    private let pinMark = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let pinButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private var palette = Palette.light

    /// A long clip's tile only needs its start, and laying out 10,000 characters per tile is waste.
    private static let shownCharacters = 300

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        thumbnail.contentMode = .scaleAspectFill
        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 3
        label.lineBreakMode = .byTruncatingTail
        pinMark.contentMode = .scaleAspectFit
        for (button, action) in [(pinButton, #selector(pinTapped)), (deleteButton, #selector(deleteTapped))] {
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        deleteButton.setTitle("Delete", for: .normal)
        [thumbnail, label, pinMark, pinButton, deleteButton].forEach { contentView.addSubview($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? palette.keyPressed : palette.key }
    }

    func show(_ item: ClipboardHistory.Item, actions: Bool, folder: URL?, palette: Palette) {
        self.palette = palette
        contentView.backgroundColor = palette.key
        switch item.content {
        case .text(let text):
            label.text = String(text.prefix(Self.shownCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
            label.textAlignment = isRightToLeft(text) ? .right : .left
            thumbnail.image = nil
        case .image(let image):
            label.text = nil
            // contentsOfFile doesn't cache, so a scrolled-away tile's pixels are freed.
            thumbnail.image = folder.flatMap { UIImage(contentsOfFile: $0.appendingPathComponent(image.thumbnail).path) }
        }
        label.textColor = palette.label
        pinMark.tintColor = palette.secondaryLabel
        pinButton.setTitle(item.pinned ? "Unpin" : "Pin", for: .normal)
        [pinButton, deleteButton].forEach { $0.setTitleColor(palette.label, for: .normal) }
        label.isHidden = actions
        thumbnail.isHidden = actions
        pinMark.isHidden = actions || !item.pinned
        pinButton.isHidden = !actions
        deleteButton.isHidden = !actions
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        thumbnail.frame = bounds
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
