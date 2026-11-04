import ImageIO
import KalamEngine
import UIKit
import UniformTypeIdentifiers
import os

/// SPEC 5.5 on the keyboard side: captures new pasteboard text or images into the history and keeps
/// `clipboard.json` and the `Clipboard/` image folder in the App Group container. Everything runs on
/// main; the file is small and is written only on clipboard actions, never on a keystroke.
final class Clipboard {
    private(set) var history = ClipboardHistory()
    /// Set when only the chip's dismissal changed, which waits for the next save or `flush`.
    private var dirty = false
    private let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Settings.appGroup)
    private var url: URL? { container?.appendingPathComponent("clipboard.json") }
    /// Image originals and their thumbnails.
    var folder: URL? { container?.appendingPathComponent("Clipboard", isDirectory: true) }
    private let defaults = UserDefaults(suiteName: Settings.appGroup)
    private static let log = Logger(subsystem: "com.morad.kalam.keyboard", category: "clipboard")
    private static let changeCountKey = "clipboardChangeCount"
    /// `changeCount` asks the pasteboard service, so host changes check at most this often (SPEC 11).
    private static let hostChangeInterval: TimeInterval = 1
    /// A tile's width at @3x, the thumbnail's longest side.
    private static let thumbnailPixels = 560
    private var lastCheck = -TimeInterval.infinity

    /// Re-reads the file on appear, so another host app's keyboard instance is picked up.
    func load() {
        history = url.map { ClipboardHistory.load(from: $0, now: Date()) } ?? ClipboardHistory()
        dirty = false
        removeUnreferencedFiles()
    }

    /// Drops expired items and, when the pasteboard changed since the last look (a lower count
    /// after a reboot counts too), adds its text or, without text, its image. `changeCount`,
    /// `hasStrings`, `hasImages` and the types are metadata; only reading the content can show iOS's
    /// paste prompt. Returns whether a clip was added.
    @discardableResult
    func capture() -> Bool {
        lastCheck = ProcessInfo.processInfo.systemUptime
        history.expire(now: Date())
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        guard let defaults, count != defaults.integer(forKey: Self.changeCountKey) else { return false }
        defaults.set(count, forKey: Self.changeCountKey)
        guard !pasteboard.contains(pasteboardTypes: ["org.nspasteboard.ConcealedType"]) else { return false }
        if pasteboard.hasStrings {
            guard let text = pasteboard.string else { return false }
            change { $0.add(text, now: Date()) }
            return true
        }
        guard pasteboard.hasImages, let image = captureImage(pasteboard) else { return false }
        change { $0.add(image, now: Date()) }
        return true
    }

    /// `capture`, unless the last check was under `hostChangeInterval` ago.
    func captureIfDue() -> Bool {
        guard ProcessInfo.processInfo.systemUptime - lastCheck >= Self.hostChangeInterval else { return false }
        return capture()
    }

    func change(_ edit: (inout ClipboardHistory) -> Void) {
        edit(&history)
        save()
        removeUnreferencedFiles()
    }

    /// Puts an image back on the pasteboard, as the keyboard can't insert it (SPEC 5.5). The new
    /// `changeCount` is remembered, so the next capture doesn't take Kalam's own write.
    func copy(_ image: ClipboardHistory.Image) -> Bool {
        guard let file = folder?.appendingPathComponent(image.file),
              let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            Self.log.error("clipboard image missing")
            return false
        }
        UIPasteboard.general.setData(data, forPasteboardType: image.type)
        defaults?.set(UIPasteboard.general.changeCount, forKey: Self.changeCountKey)
        return true
    }

    /// Typing hides the chip for good; saved later, so the keystroke never writes the file.
    func dismissChip() {
        guard history.chip(now: Date()) != nil else { return }
        history.useChip()
        dirty = true
    }

    func flush() {
        if dirty { save() }
    }

    private func save() {
        if let url { history.save(to: url) }
        dirty = false
    }

    private func removeUnreferencedFiles() {
        if let folder { history.removeUnreferencedFiles(in: folder) }
    }

    /// Writes the first image type's raw bytes and a JPEG thumbnail. The original is never decoded
    /// (no `UIImage`): a large photo would push the keyboard past its memory limit. ImageIO makes
    /// the thumbnail straight from the encoded data.
    private func captureImage(_ pasteboard: UIPasteboard) -> ClipboardHistory.Image? {
        guard let folder,
              let type = pasteboard.types.first(where: { UTType($0)?.conforms(to: .image) == true }),
              let data = pasteboard.data(forPasteboardType: type), data.count <= ClipboardHistory.maxImageBytes else { return nil }
        let image = ClipboardHistory.Image(data: data, type: type)
        let original = folder.appendingPathComponent(image.file)
        guard !FileManager.default.fileExists(atPath: original.path) else { return image }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeThumbnail(of: data, to: folder.appendingPathComponent(image.thumbnail))
            try data.write(to: original, options: .atomic)
            return image
        } catch {
            Self.log.error("clipboard image not saved: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func writeThumbnail(of data: Data, to url: URL) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailPixels,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
