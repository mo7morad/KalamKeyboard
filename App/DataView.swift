import CoreTransferable
import KalamEngine
import SwiftUI
import UniformTypeIdentifiers

struct DataView: View {
    @Environment(StoreHolder.self) private var holder
    @State private var stats = StoreStats()
    @State private var confirmingReset = false
    @State private var choosingBackup = false
    @State private var backupToRestore: URL?
    @State private var restoring = false
    @State private var error: String?

    private static let langs = [("en", "English"), ("ar", "Arabic"), ("tok", "Emails and Handles")]

    var body: some View {
        List {
            ForEach(Self.langs, id: \.0) { lang, title in
                let words = stats.words[lang] ?? StoreStats.Words()
                Section(title) {
                    LabeledContent("Known", value: words.known, format: .number)
                    LabeledContent("Pending", value: words.pending, format: .number)
                    LabeledContent("Blocked", value: words.blocked, format: .number)
                }
            }
            Section {
                LabeledContent("Word Sequences", value: stats.ngrams, format: .number)
                LabeledContent("Corrections", value: stats.corrections, format: .number)
            } header: {
                Text("Patterns")
            }
            Section {
                ShareLink(item: StoreBackup(), preview: SharePreview("Kalam Backup")) {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                Button { choosingBackup = true } label: {
                    Label(restoring ? "Restoring…" : "Restore from Backup", systemImage: "arrow.counterclockwise")
                }
                .disabled(restoring)
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup holds everything Kalam has learned. Restoring replaces it.")
            }
            Section {
                Button("Reset Learning", role: .destructive) { confirmingReset = true }
            }
        }
        .navigationTitle("Data")
        .task(id: "\(holder.revision)|\(holder.store == nil)") { reload() }
        .confirmationDialog("Delete everything Kalam has learned?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Learning", role: .destructive) {
                do { try holder.write { try $0.resetLearning() } } catch { self.error = message(error) }
            }
        } message: {
            Text("This can't be undone. Export a backup first to keep a copy.")
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.item]) { picked in
            switch picked {
            case .success(let url): backupToRestore = url
            case .failure(let failure): error = message(failure)
            }
        }
        .confirmationDialog("Replace everything Kalam has learned with this backup?",
                            isPresented: Binding(get: { backupToRestore != nil }, set: { if !$0 { backupToRestore = nil } }),
                            titleVisibility: .visible, presenting: backupToRestore) { url in
            Button("Restore", role: .destructive) { restore(url) }
        }
        .errorAlert($error)
    }

    private func reload() {
        guard let store = holder.store else { return }
        do { stats = try store.stats() } catch { self.error = message(error) }
    }

    private func restore(_ url: URL) {
        restoring = true
        Task {
            do {
                try await StoreHolder.inBackground { store in
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    try store.restore(from: url)
                }
                holder.changed()
            } catch {
                self.error = message(error)
            }
            restoring = false
        }
    }
}

/// The store as a file, made when the share sheet asks for it.
struct StoreBackup: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { _ in
            let name = "Kalam Backup \(Date().formatted(.iso8601.year().month().day())).sqlite"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            try await StoreHolder.inBackground { try $0.backup(to: url) }
            return SentTransferredFile(url)
        }
    }
}
