import CryptoKit
import Foundation
import os

private let clipboardLog = Logger(subsystem: "com.morad.kalam", category: "clipboard")

/// The clipboard history (SPEC 5.5): copied texts and images, newest first, kept in `clipboard.json`.
/// Each content appears once, so it is its own identity. Pinned items stay until deleted; the others expire.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    /// A copied image: its original and a JPEG thumbnail are files in the clipboard folder.
    public struct Image: Codable, Equatable, Sendable {
        /// The original's file, named by the SHA-256 of its bytes, so the same image is the same file.
        public let file: String
        /// Its pasteboard type, e.g. `public.png`.
        public let type: String

        public init(data: Data, type: String) {
            file = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            self.type = type
        }

        public var thumbnail: String { file + "-thumb.jpg" }
    }

    public enum Content: Equatable, Sendable {
        case text(String)
        case image(Image)
    }

    public struct Item: Equatable, Sendable {
        public let content: Content
        public let captured: Date
        public var pinned: Bool
    }

    public static let maxCharacters = 10_000
    /// Larger images are skipped: capturing reads the whole original into memory.
    public static let maxImageBytes = 20_000_000
    public static let maxItems = 50
    /// Unpinned items go this long after they were captured, as in Gboard.
    public static let lifetime: TimeInterval = 3600
    /// How long a new clip is offered as the bar's chip.
    public static let chipLifetime: TimeInterval = 120

    /// Newest capture first.
    public private(set) var items: [Item] = []
    /// Whether the newest clip was already pasted or dismissed, so the chip stays away.
    private var chipUsed = false

    public init() {}

    /// The panel's order: pinned first, then newest first.
    public var panelItems: [Item] { items.filter(\.pinned) + items.filter { !$0.pinned } }

    /// The bar's chip: the newest clip's text, if it was captured within `chipLifetime` and not yet
    /// used. An image gets no chip: it is on the pasteboard already, so the field's Paste works.
    public func chip(now: Date) -> String? {
        guard !chipUsed, let newest = items.first, now.timeIntervalSince(newest.captured) <= Self.chipLifetime,
              case .text(let text) = newest.content else { return nil }
        return text
    }

    /// Adds a copied text on top. Blank or over-long texts are skipped.
    public mutating func add(_ text: String, now: Date) {
        guard !text.allSatisfy(\.isWhitespace), text.count <= Self.maxCharacters else { return }
        add(.text(text), now: now)
    }

    public mutating func add(_ image: Image, now: Date) { add(.image(image), now: now) }

    /// A known content moves to the top with a fresh capture date and keeps its pin. Past
    /// `maxItems`, the oldest unpinned go.
    private mutating func add(_ content: Content, now: Date) {
        let pinned = items.first { $0.content == content }?.pinned ?? false
        delete(content)
        items.insert(Item(content: content, captured: now, pinned: pinned), at: 0)
        chipUsed = false
        expire(now: now)
        while items.count > Self.maxItems, let oldest = items.lastIndex(where: { !$0.pinned }) {
            items.remove(at: oldest)
        }
    }

    public mutating func useChip() { chipUsed = true }

    public mutating func setPinned(_ pinned: Bool, _ content: Content) {
        guard let i = items.firstIndex(where: { $0.content == content }) else { return }
        items[i].pinned = pinned
    }

    public mutating func delete(_ content: Content) { items.removeAll { $0.content == content } }

    /// "Clear" deletes the unpinned items.
    public mutating func clear() { items.removeAll { !$0.pinned } }

    public mutating func expire(now: Date) {
        items.removeAll { !$0.pinned && now.timeIntervalSince($0.captured) > Self.lifetime }
    }

    // MARK: Files

    /// Deletes the files in `folder` that no item references, such as a deleted or expired image's
    /// original and thumbnail.
    public func removeUnreferencedFiles(in folder: URL) {
        let referenced = Set(items.flatMap { item -> [String] in
            guard case .image(let image) = item.content else { return [] }
            return [image.file, image.thumbnail]
        })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !referenced.contains(file) {
            do {
                try FileManager.default.removeItem(at: folder.appendingPathComponent(file))
            } catch {
                clipboardLog.error("clipboard file not removed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reads the history and drops the expired items. A missing or unreadable file is an empty history.
    public static func load(from url: URL, now: Date) -> ClipboardHistory {
        var history = ClipboardHistory()
        do {
            history = try JSONDecoder().decode(ClipboardHistory.self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            clipboardLog.info("no clipboard history yet")
        } catch {
            clipboardLog.error("clipboard history unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
        }
        history.expire(now: now)
        return history
    }

    /// Writes atomically (a temporary file renamed over the old one), so no lock is ever held.
    public func save(to url: URL) {
        do {
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        } catch {
            clipboardLog.error("clipboard history not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The file format predates images: a text item is `{"text", "captured", "pinned"}`, and an image
/// item has `"image"` in place of `"text"`, so old files still load.
extension ClipboardHistory.Item: Codable {
    private enum CodingKeys: String, CodingKey { case text, image, captured, pinned }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let image = try values.decodeIfPresent(ClipboardHistory.Image.self, forKey: .image) {
            content = .image(image)
        } else {
            content = .text(try values.decode(String.self, forKey: .text))
        }
        captured = try values.decode(Date.self, forKey: .captured)
        pinned = try values.decode(Bool.self, forKey: .pinned)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch content {
        case .text(let text): try values.encode(text, forKey: .text)
        case .image(let image): try values.encode(image, forKey: .image)
        }
        try values.encode(captured, forKey: .captured)
        try values.encode(pinned, forKey: .pinned)
    }
}
