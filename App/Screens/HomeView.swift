import SwiftUI

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
