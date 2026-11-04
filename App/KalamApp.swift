import SwiftUI

@main
struct KalamApp: App {
    @State private var store = StoreHolder()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                // An idle WAL connection holds a lock on -shm; suspending with it gets the app killed (0xdead10cc).
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { store.open() } else if phase == .background { store.close() }
                }
        }
    }
}

struct HomeView: View {
    @Environment(StoreHolder.self) private var holder
    @State private var keyboardAdded = KeyboardStatus.isAdded

    var body: some View {
        NavigationStack {
            List {
                if let openError = holder.openError {
                    Section {
                        Label("Can't open the learned data: \(openError)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    NavigationLink { SetupView() } label: {
                        LabeledContent {
                            Text(keyboardAdded == true ? "Added" : keyboardAdded == false ? "Not Added" : "")
                        } label: {
                            Label("Set Up Keyboard", systemImage: "keyboard")
                        }
                    }
                    NavigationLink { TryItView() } label: { Label("Try It", systemImage: "character.cursor.ibeam") }
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }
                Section("Learning") {
                    NavigationLink { WordsView() } label: { Label("Learned Words", systemImage: "text.book.closed") }
                    NavigationLink { ImportView() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    NavigationLink { DataView() } label: { Label("Data", systemImage: "externaldrive") }
                }
            }
            .navigationTitle("Kalam")
            .onAppear { keyboardAdded = KeyboardStatus.isAdded }
        }
    }
}

struct TryItView: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Type here", text: $text, axis: .vertical)
                    .lineLimit(6...)
                    .focused($focused)
            } footer: {
                Text("Hold or tap the globe key to switch to Kalam.")
            }
        }
        .navigationTitle("Try It")
        .onAppear { focused = true }
    }
}
