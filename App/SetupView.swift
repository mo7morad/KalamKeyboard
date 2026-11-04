import SwiftUI

struct SetupView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var added = KeyboardStatus.isAdded

    private let steps = [
        "Tap Open Settings below, then tap Keyboards.",
        "Turn on Kalam.",
        "Turn on Allow Full Access. Kalam needs it to learn your words and read these settings.",
        "Go back to Kalam's page and set Paste from Other Apps to Allow, so the clipboard never has to ask.",
        "In any text field, tap or hold the globe key and choose Kalam.",
    ]

    var body: some View {
        List {
            if let added {
                Section {
                    Label(added ? "Kalam is added" : "Kalam isn't added yet",
                          systemImage: added ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(added ? .green : .secondary)
                }
            }
            Section("Steps") {
                ForEach(steps.indices, id: \.self) { i in
                    Label { Text(steps[i]) } icon: { Image(systemName: "\(i + 1).circle") }
                }
            }
            Section {
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            } footer: {
                Text("Full Access lets the keyboard save what it learns where this app can see it. Kalam sends nothing anywhere.")
            }
        }
        .navigationTitle("Set Up")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { added = KeyboardStatus.isAdded }
        }
    }
}
