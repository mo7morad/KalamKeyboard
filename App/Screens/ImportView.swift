import KalamEngine
import SwiftUI

struct ImportView: View {
    @Environment(StoreHolder.self) private var holder
    @State private var choosingFile = false
    @State private var messages: [ChatMessage] = []
    @State private var senders: [(sender: String, messages: Int)] = []
    @State private var chosen: Set<String> = []
    @State private var pasted = ""
    @State private var working: String?
    @State private var result: String?
    @State private var error: String?
    private static let hasLexicons = BaseLexicons.load().count == 2

    /// The senders Moe picked last time; his name in his own exports.
    private static let sendersKey = "importSenders"
    private static let defaultSender = "Mohamed Morad"

    var body: some View {
        Form {
            Section {
                Button("Choose _chat.txt") { choosingFile = true }
            } header: {
                Text("WhatsApp Chat")
            } footer: {
                Text("In WhatsApp, export a chat without media and save it to Files. Unzip it there, then choose _chat.txt.")
            }
            if !senders.isEmpty {
                Section {
                    ForEach(senders, id: \.sender) { sender in
                        Button { toggle(sender.sender) } label: {
                            LabeledContent(sender.sender, value: "\(sender.messages) messages")
                        }
                        .tint(.primary)
                        .badge(chosen.contains(sender.sender) ? Text(Image(systemName: "checkmark")) : nil)
                    }
                    Button("Learn \(chosenCount) Messages") { importChat() }
                        .disabled(chosen.isEmpty || working != nil)
                } header: {
                    Text("Which Senders Are You?")
                } footer: {
                    Text("Only the messages of the senders you check are learned.")
                }
            }
            Section("Paste Text to Learn") {
                TextField("Text you wrote", text: $pasted, axis: .vertical)
                    .lineLimit(4...)
                Button("Learn Text") { importPasted() }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working != nil)
            }
            if let working {
                Section { ProgressView { Text(working) } }
            } else if let result {
                Section("Result") { Text(result) }
            }
            if !Self.hasLexicons {
                Section {
                    Label("This build has no base word lists, so import can't spot typos or lazy spellings like dont. Words are still learned.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Import")
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.plainText]) { picked in
            if case .success(let url) = picked { load(url) } else if case .failure(let failure) = picked { error = message(failure) }
        }
        .errorAlert($error)
    }

    private var chosenCount: Int { senders.filter { chosen.contains($0.sender) }.reduce(0) { $0 + $1.messages } }

    private func toggle(_ sender: String) {
        if chosen.remove(sender) == nil { chosen.insert(sender) }
    }

    private func load(_ url: URL) {
        run("Reading the chat") {
            let parsed = try await Task.detached {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return parseWhatsApp(try String(contentsOf: url, encoding: .utf8))
            }.value
            messages = parsed
            senders = senderCounts(parsed)
            let last = Set(UserDefaults.standard.stringArray(forKey: Self.sendersKey) ?? [Self.defaultSender])
            chosen = last.intersection(senders.map(\.sender))
            if parsed.isEmpty { result = "No messages found in this file." }
        }
    }

    private func importChat() {
        UserDefaults.standard.set(Array(chosen), forKey: Self.sendersKey)
        let (messages, chosen, count) = (messages, chosen, chosenCount)
        learn("Learning \(count) messages", what: "\(count) messages") { store, lexicons, settings in
            try store.importChat(messages, senders: chosen, lexicons: lexicons, settings: settings)
        }
    }

    private func importPasted() {
        let text = pasted
        learn("Learning the text", what: "The text") { store, lexicons, settings in
            try store.importTexts([(text, nil)], lexicons: lexicons, settings: settings)
        }
        pasted = ""
    }

    /// Imports on a background connection, then reports how many words are new.
    private func learn(_ label: String, what: String, _ work: @escaping (PersonalStore, [BaseLexicon], Settings) throws -> Void) {
        run(label) {
            let (before, after) = try await StoreHolder.inBackground { store in
                let before = try store.stats()
                try work(store, BaseLexicons.load(), Settings.load())
                return (before, try store.stats())
            }
            result = "\(what) learned. \(Self.summary(before: before, after: after))"
            holder.changed()
        }
    }

    /// Shows `label` with a spinner while `work` runs, and any error it throws.
    private func run(_ label: String, _ work: @escaping () async throws -> Void) {
        (working, result) = (label, nil)
        Task {
            do { try await work() } catch { self.error = message(error) }
            working = nil
        }
    }

    /// Totals across languages, since a new word can be pending while an older one turns known.
    private static func summary(before: StoreStats, after: StoreStats) -> String {
        func total(_ stats: StoreStats, _ state: KeyPath<StoreStats.Words, Int>) -> Int { stats.words.values.reduce(0) { $0 + $1[keyPath: state] } }
        let added = total(after, \.known) + total(after, \.pending) - total(before, \.known) - total(before, \.pending)
        return "New words: \(added). Known: \(total(after, \.known)), pending: \(total(after, \.pending))."
    }
}
