import SwiftUI

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
