import KalamEngine
import SwiftUI

struct WordsView: View {
    @Environment(StoreHolder.self) private var holder
    @State private var lang = "en"
    @State private var search = ""
    @State private var words: [LearnedWord] = []
    @State private var adding = false
    @State private var newWord = ""
    @State private var error: String?

    private static let langs = [("en", "English"), ("ar", "العربية"), ("tok", "Other")]

    var body: some View {
        List {
            Section {
                Picker("Language", selection: $lang) {
                    ForEach(Self.langs, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ForEach(words) { word in
                    WordRow(word: word)
                        .swipeActions {
                            Button("Forget", role: .destructive) { perform { try $0.forget(lang: word.lang, ident: word.ident) } }
                            if word.state == .blocked {
                                Button("Unblock") { perform { try $0.addManually(word.display) } }.tint(.blue)
                            } else {
                                Button("Block") { perform { try $0.block(word) } }.tint(.orange)
                            }
                        }
                }
            } footer: {
                if !words.isEmpty { Text("Swipe left to forget or block a word. Blocked words are never suggested.") }
            }
        }
        .overlay {
            if words.isEmpty {
                if search.isEmpty { ContentUnavailableView("No Words Yet", systemImage: "text.book.closed",
                                                           description: Text("Words you type or import appear here.")) }
                else { ContentUnavailableView.search(text: search) }
            }
        }
        .navigationTitle("Learned Words")
        .searchable(text: $search)
        .toolbar {
            Button("Add Word", systemImage: "plus") { adding = true }
        }
        .alert("Add Word", isPresented: $adding) {
            TextField("Word", text: $newWord)
            Button("Cancel", role: .cancel) { newWord = "" }
            Button("Add") {
                perform { try $0.addManually(newWord) }
                newWord = ""
            }
        } message: {
            Text("Kalam will suggest it and never correct it.")
        }
        .task(id: "\(lang)|\(search)|\(holder.revision)|\(holder.store == nil)") { reload() }
        .errorAlert($error)
    }

    private func reload() {
        guard let store = holder.store else { return }
        do { words = try store.learnedWords(lang: lang, search: search) } catch { self.error = message(error) }
    }

    private func perform(_ work: (PersonalStore) throws -> Void) {
        do { try holder.write(work) } catch { self.error = message(error) }
    }
}

private struct WordRow: View {
    let word: LearnedWord

    var body: some View {
        HStack {
            Text(word.display)
            if word.state != .known {
                Text(word.state == .blocked ? "Blocked" : "Pending")
                    .font(.caption)
                    .foregroundStyle(word.state == .blocked ? .orange : .secondary)
            }
            Spacer()
            Text(word.count, format: .number.precision(.fractionLength(0)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        // An Arabic row reads from the right, like the keyboard.
        .environment(\.layoutDirection, word.lang == "ar" ? .rightToLeft : .leftToRight)
    }
}
