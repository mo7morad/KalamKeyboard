import KalamEngine
import UIKit

/// SPEC 5.5 on the keyboard side: captures new pasteboard text into the history and keeps
/// `clipboard.json` in the App Group container. Everything runs on main; the file is small and is
/// written only on clipboard actions, never on a keystroke.
final class Clipboard {
    private(set) var history = ClipboardHistory()
    /// Set when only the chip's dismissal changed, which waits for the next save or `flush`.
    private var dirty = false
    private let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Settings.appGroup)?
        .appendingPathComponent("clipboard.json")
    private let defaults = UserDefaults(suiteName: Settings.appGroup)
    private static let changeCountKey = "clipboardChangeCount"
    /// `changeCount` asks the pasteboard service, so host changes check at most this often (SPEC 11).
    private static let hostChangeInterval: TimeInterval = 1
    private var lastCheck = -TimeInterval.infinity

    /// Re-reads the file on appear, so another host app's keyboard instance is picked up.
    func load() {
        history = url.map { ClipboardHistory.load(from: $0, now: Date()) } ?? ClipboardHistory()
        dirty = false
    }

    /// Drops expired items and, when the pasteboard changed since the last look (a lower count
    /// after a reboot counts too), adds its text. `changeCount`, `hasStrings` and the type check are
    /// metadata; only `string` can show iOS's paste prompt. Returns whether a clip was added.
    @discardableResult
    func capture() -> Bool {
        lastCheck = ProcessInfo.processInfo.systemUptime
        history.expire(now: Date())
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        guard let defaults, count != defaults.integer(forKey: Self.changeCountKey) else { return false }
        defaults.set(count, forKey: Self.changeCountKey)
        guard pasteboard.hasStrings, !pasteboard.contains(pasteboardTypes: ["org.nspasteboard.ConcealedType"]),
              let text = pasteboard.string else { return false }
        change { $0.add(text, now: Date()) }
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
}
