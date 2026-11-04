import SwiftUI
import UIKit

@main
struct HarnessApp: App {
    var body: some Scene { WindowGroup { Field().padding(.top, 60) } }
}

/// A UITextView that grabs focus as soon as it is on screen.
struct Field: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.font = .systemFont(ofSize: 20)
        v.accessibilityIdentifier = "field"
        if ProcessInfo.processInfo.arguments.contains("-noPredict") {
            v.autocorrectionType = .no
            v.spellCheckingType = .no
            v.inlinePredictionType = .no
        }
        if ProcessInfo.processInfo.arguments.contains("-images") { v.allowsEditingTextAttributes = true }  // takes pasted images
        forceSoftwareKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { v.becomeFirstResponder() }
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) {}
}

/// Headless simulators act as if a hardware keyboard is attached; this KIF-style
/// private-API poke makes the on-screen keyboard show anyway.
func forceSoftwareKeyboard() {
    if let c = NSClassFromString("UIKeyboardPreferencesController") as? NSObject.Type,
       let pc = c.perform(NSSelectorFromString("sharedPreferencesController"))?.takeUnretainedValue() as? NSObject {
        _ = pc.perform(NSSelectorFromString("setValue:forPreferenceKey:"), with: false as NSNumber, with: "AutomaticMinimizationEnabled")
    }
    if let c = NSClassFromString("UIKeyboardImpl") as? NSObject.Type,
       let impl = c.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue() as? NSObject {
        _ = impl.perform(NSSelectorFromString("setAutomaticMinimizationEnabled:"), with: nil)
        _ = impl.perform(NSSelectorFromString("setInHardwareKeyboardMode:"), with: nil)
    }
}
