import KalamEngine
import SwiftUI

/// The app's connection to the shared personal store. It's open only while the app is active
/// (KalamApp closes it in the background), and `revision` changes after every write so screens reload.
@MainActor @Observable
final class StoreHolder {
    private(set) var store: PersonalStore?
    private(set) var openError: String?
    private(set) var revision = 0

    func open() {
        guard store == nil else { return }
        do {
            store = try PersonalStore(url: Self.url())
            openError = nil
        } catch {
            openError = message(error)
        }
    }

    func close() { store = nil }

    func changed() { revision += 1 }

    /// Runs a quick write on the app's connection, then reloads the screens.
    func write(_ work: (PersonalStore) throws -> Void) throws {
        guard let store else { throw StoreUnavailable() }
        try work(store)
        changed()
    }

    /// Runs long work (import, backup, restore) on its own connection off the main thread, under a
    /// background task so iOS doesn't suspend the app while that connection holds a lock.
    nonisolated static func inBackground<T>(_ work: @escaping (PersonalStore) throws -> T) async throws -> T {
        let url = try url()
        let task = await UIApplication.shared.beginBackgroundTask(withName: "Kalam store")
        defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(task) } }
        return try await Task.detached { try work(PersonalStore(url: url)) }.value
    }

    nonisolated private static func url() throws -> URL {
        guard let url = PersonalStore.sharedURL else { throw StoreUnavailable() }
        return url
    }
}

/// The base lexicons ship inside the keyboard extension. They're build outputs, so a build may lack
/// them; import then runs without the typo and lazy-spelling rules.
enum BaseLexicons {
    static func load() -> [BaseLexicon] {
        guard let appex = Bundle.main.builtInPlugInsURL?.appendingPathComponent("KalamKeyboard.appex") else { return [] }
        return [Lang.en, .ar].compactMap { BaseLexicon(url: appex.appendingPathComponent("\($0.rawValue).klex")) }
    }
}

enum KeyboardStatus {
    /// Whether Kalam is in Settings > Keyboards, from the global AppleKeyboards preference; nil if unreadable.
    static var isAdded: Bool? {
        (UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String])?.contains("com.morad.kalam.keyboard")
    }
}
