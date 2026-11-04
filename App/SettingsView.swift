import KalamEngine
import SwiftUI

/// Every SPEC 10 setting, saved to App Group UserDefaults on each change; the keyboard reads them.
struct SettingsView: View {
    @State private var settings = Settings.load()

    var body: some View {
        Form {
            Section("Feedback") {
                Toggle("Haptics", isOn: $settings.haptics)
                LabeledContent("Strength") {
                    Slider(value: $settings.hapticStrength, in: 0.3...1)  // SPEC 5.3
                }
                .disabled(!settings.haptics)
                Toggle("Key Sounds", isOn: $settings.sounds)
            }
            Section {
                autocorrectPicker("English Autocorrect", selection: $settings.autocorrectEN)
                autocorrectPicker("Arabic Autocorrect", selection: $settings.autocorrectAR)
                Toggle("Fix English Contractions", isOn: $settings.contractionFix)
                Toggle("Fix Arabic Spelling Variants", isOn: $settings.arabicVariantFix)
            } header: {
                Text("Correction")
            } footer: {
                Text("Contractions: dont becomes don't. Arabic variants: انا becomes أنا. Variants are always offered as suggestions.")
            }
            Section("Typing") {
                Toggle("Auto-Capitalization", isOn: $settings.autoCapitalize)
                Toggle("\u{201C}.\u{201D} Shortcut", isOn: $settings.doubleSpacePeriod)
                Toggle("Digit Hints on Top Row", isOn: $settings.digitHints)
                Toggle("Eastern Arabic Digits", isOn: $settings.easternArabicDigits)
            }
            Section {
                Toggle("Clipboard", isOn: $settings.clipboard)
            } footer: {
                Text("The keyboard keeps what you copy for an hour; pinned items stay until you delete them. If iOS asks before Kalam can paste, set Settings \u{203A} Apps \u{203A} Kalam \u{203A} Paste from Other Apps to Allow.")
            }
            Section {
                Toggle("Pause Learning", isOn: $settings.pauseLearning)
            } footer: {
                Text("While paused, the keyboard learns no new words.")
            }
            #if DEBUG
            Section("Debug") {
                Toggle("Debug Overlay", isOn: $settings.debugOverlay)
            }
            #endif
        }
        .navigationTitle("Settings")
        .onChange(of: settings) { _, new in new.save() }
    }

    private func autocorrectPicker(_ title: String, selection: Binding<AutocorrectMode>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AutocorrectMode.allCases, id: \.self) { Text($0.rawValue.capitalized) }
        }
    }
}
