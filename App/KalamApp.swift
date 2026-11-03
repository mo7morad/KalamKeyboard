import SwiftUI

@main
struct KalamApp: App {
    @State private var text = ""

    var body: some Scene {
        WindowGroup {
            TextField("Try Kalam here", text: $text, axis: .vertical)
                .padding()
        }
    }
}
