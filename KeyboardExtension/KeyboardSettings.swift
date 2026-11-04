import KalamEngine
import UIKit

/// The keyboard's settings with the SPEC §10 defaults. This is the one place the extension reads
/// them from; Phase 5 swaps the defaults for the shared App Group settings.
struct KeyboardSettings {
    var haptics = true
    var hapticStrength: CGFloat = 0.7
    var sounds = true
    var autoCapitalize = true
    var doubleSpacePeriod = true
    var digitHints = true
    /// SPEC §10 says off; on until Phase 5 adds a switch, so Debug builds can show the overlay.
    var debugOverlay = true

    static let current = KeyboardSettings()

    private static let lastLanguageKey = "lastLanguage"

    /// The last EN/AR choice, kept in the extension's own defaults (App Group writes need Full Access).
    static var lastLanguage: Lang {
        get { UserDefaults.standard.string(forKey: lastLanguageKey).flatMap(Lang.init(rawValue:)) ?? .en }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastLanguageKey) }
    }
}
