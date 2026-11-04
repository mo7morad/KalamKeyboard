import Foundation

public enum AutocorrectMode: String, CaseIterable, Sendable {
    case off, gentle, normal
}

/// User settings (SPEC 10), shared by the keyboard and the host app through App Group UserDefaults.
/// Each UserDefaults key is the property name; a missing or malformed value keeps the default.
public struct Settings: Equatable, Sendable {
    public static let appGroup = "group.com.morad.kalam"

    public var haptics = true
    public var hapticStrength = 0.7
    public var sounds = true
    public var autocorrectEN = AutocorrectMode.normal
    public var autocorrectAR = AutocorrectMode.gentle
    public var autoCapitalize = true
    public var doubleSpacePeriod = true
    public var contractionFix = true  // EN variant fix, e.g. dont -> don't
    public var arabicVariantFix = false  // AR variant fix, e.g. انا -> أنا (D8)
    public var easternArabicDigits = false
    public var digitHints = true
    public var pauseLearning = false
    public var clipboard = true  // SPEC 5.5
    public var debugOverlay = false  // honored in Debug builds only

    public init() {}

    private static let bools: [String: WritableKeyPath<Settings, Bool>] = [
        "haptics": \.haptics, "sounds": \.sounds, "autoCapitalize": \.autoCapitalize,
        "doubleSpacePeriod": \.doubleSpacePeriod, "contractionFix": \.contractionFix,
        "arabicVariantFix": \.arabicVariantFix, "easternArabicDigits": \.easternArabicDigits,
        "digitHints": \.digitHints, "pauseLearning": \.pauseLearning, "clipboard": \.clipboard, "debugOverlay": \.debugOverlay,
    ]
    private static let modes: [String: WritableKeyPath<Settings, AutocorrectMode>] = [
        "autocorrectEN": \.autocorrectEN, "autocorrectAR": \.autocorrectAR,
    ]

    /// Reads the settings; nil defaults (no App Group access) gives the defaults.
    public static func load(from defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> Settings {
        var settings = Settings()
        guard let defaults else { return settings }
        for (key, path) in bools {
            if let value = defaults.object(forKey: key) as? Bool { settings[keyPath: path] = value }
        }
        for (key, path) in modes {
            if let value = defaults.string(forKey: key).flatMap(AutocorrectMode.init) { settings[keyPath: path] = value }
        }
        if let value = defaults.object(forKey: "hapticStrength") as? Double { settings.hapticStrength = value }
        return settings
    }

    /// Writes every setting; nil defaults (no App Group access) writes nothing.
    public func save(to defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        guard let defaults else { return }
        for (key, path) in Self.bools { defaults.set(self[keyPath: path], forKey: key) }
        for (key, path) in Self.modes { defaults.set(self[keyPath: path].rawValue, forKey: key) }
        defaults.set(hapticStrength, forKey: "hapticStrength")
    }

    public func autocorrect(_ lang: Lang) -> AutocorrectMode { lang == .en ? autocorrectEN : autocorrectAR }
    public func variantFix(_ lang: Lang) -> Bool { lang == .en ? contractionFix : arabicVariantFix }
}

/// What the engine needs from UITextInputTraits; the keyboard maps UIKit to these.
public struct FieldTraits: Equatable, Sendable {
    public enum KeyboardType: Sendable { case url, email, other }
    public enum ContentType: Sendable { case password, oneTimeCode, other }

    public var autocorrection: Bool
    public var keyboardType: KeyboardType
    public var contentType: ContentType

    public init(autocorrection: Bool = true, keyboardType: KeyboardType = .other, contentType: ContentType = .other) {
        self.autocorrection = autocorrection
        self.keyboardType = keyboardType
        self.contentType = contentType
    }

    /// SPEC 8.5 rule 1 (the per-language setting is checked separately).
    public var allowsAutocorrect: Bool { autocorrection && keyboardType == .other && contentType == .other }
    /// SPEC 9.2: no learning in URL, password and one-time-code fields.
    public var allowsLearning: Bool { keyboardType != .url && contentType == .other }
}
