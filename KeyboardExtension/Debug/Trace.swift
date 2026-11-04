import KalamEngine
import QuartzCore

/// Debug builds only: one line per touch, commit and host change, appended to
/// `<App Group>/Library/Caches/kalam-trace.log` for a device run (devicectl can pull Library).
/// Release builds compile every call to nothing.
@inline(__always)
func trace(_ line: @autoclosure () -> String) {
    #if DEBUG
    Trace.shared?.write(line())
    #endif
}

#if DEBUG
final class Trace {
    static let shared = Trace()

    private static let maxBytes: UInt64 = 1_000_000
    private let url: URL

    private init?() {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Settings.appGroup) else { return nil }
        let caches = group.appendingPathComponent("Library/Caches", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        url = caches.appendingPathComponent("kalam-trace.log")
    }

    /// Opens the file for every line, so pulling or deleting it between runs is always safe.
    func write(_ line: String) {
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        handle.write(Data(String(format: "%.1f %@\n", CACurrentMediaTime() * 1000, line).utf8))
        if size > Self.maxBytes { rotate() }
    }

    /// Past 1 MB the log starts over; the previous one stays as kalam-trace.1.log.
    private func rotate() {
        let old = url.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}
#endif
