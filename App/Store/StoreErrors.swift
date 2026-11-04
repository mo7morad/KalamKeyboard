import KalamEngine
import SwiftUI

struct StoreUnavailable: LocalizedError {
    var errorDescription: String? { "The shared App Group container isn't available." }
}

extension StoreError: @retroactive LocalizedError {
    public var errorDescription: String? { "This file isn't a Kalam backup." }
}

/// An error as alert text: its localized description if it has one, else its debug description.
func message(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
}

extension View {
    /// Shows `message` in an alert while it's non-nil.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Something Went Wrong", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK") {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
