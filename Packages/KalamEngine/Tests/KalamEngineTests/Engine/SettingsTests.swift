import Foundation
import Testing
@testable import KalamEngine

@Test func settingsLoadStoredValuesAndKeepDefaultsForTheRest() throws {
    let suite = "kalam-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "sounds")
    defaults.set(0.4, forKey: "hapticStrength")
    defaults.set("off", forKey: "autocorrectEN")
    defaults.set("loud", forKey: "autocorrectAR")  // malformed: keeps the default
    var expected = Settings()
    (expected.sounds, expected.hapticStrength, expected.autocorrectEN) = (false, 0.4, .off)
    #expect(Settings.load(from: defaults) == expected)
}

@Test func missingAppGroupGivesTheSpecDefaults() {
    let settings = Settings.load(from: nil)
    #expect(settings == Settings())
    #expect((settings.autocorrect(.en), settings.autocorrect(.ar)) == (.normal, .gentle))
    #expect((settings.variantFix(.en), settings.variantFix(.ar)) == (true, false))
    #expect(settings.clipboard)
}

@Test func savedSettingsLoadBack() throws {
    let suite = "kalam-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var settings = Settings()
    (settings.haptics, settings.hapticStrength, settings.autocorrectAR, settings.pauseLearning) = (false, 0.3, .off, true)
    (settings.clipboard, settings.soundBoost) = (false, 0.5)
    settings.save(to: defaults)
    #expect(Settings.load(from: defaults) == settings)
}
