import Foundation
import os

private let clipboardLog = Logger(subsystem: "com.morad.kalam", category: "clipboard")

/// The clipboard history (SPEC 5.5): copied texts, newest first, kept in `clipboard.json`. Each text
/// appears once, so it is its own identity. Pinned items stay until deleted; the others expire.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let text: String
        public let captured: Date
        public var pinned: Bool
    }

    public static let maxCharacters = 10_000
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

    /// The bar's chip: the newest clip, if it was captured within `chipLifetime` and not yet used.
    public func chip(now: Date) -> Item? {
        guard !chipUsed, let newest = items.first, now.timeIntervalSince(newest.captured) <= Self.chipLifetime else { return nil }
        return newest
    }

    /// Adds a copied text on top. Blank or over-long texts are skipped; a known text moves to the
    /// top with a fresh capture date and keeps its pin. Past `maxItems`, the oldest unpinned go.
    public mutating func add(_ text: String, now: Date) {
        guard !text.allSatisfy(\.isWhitespace), text.count <= Self.maxCharacters else { return }
        let pinned = items.first { $0.text == text }?.pinned ?? false
        delete(text)
        items.insert(Item(text: text, captured: now, pinned: pinned), at: 0)
        chipUsed = false
        expire(now: now)
        while items.count > Self.maxItems, let oldest = items.lastIndex(where: { !$0.pinned }) {
            items.remove(at: oldest)
        }
    }

    public mutating func useChip() { chipUsed = true }

    public mutating func setPinned(_ pinned: Bool, text: String) {
        guard let i = items.firstIndex(where: { $0.text == text }) else { return }
        items[i].pinned = pinned
    }

    public mutating func delete(_ text: String) { items.removeAll { $0.text == text } }

    /// "Clear" deletes the unpinned items.
    public mutating func clear() { items.removeAll { !$0.pinned } }

    public mutating func expire(now: Date) {
        items.removeAll { !$0.pinned && now.timeIntervalSince($0.captured) > Self.lifetime }
    }

    // MARK: File

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
