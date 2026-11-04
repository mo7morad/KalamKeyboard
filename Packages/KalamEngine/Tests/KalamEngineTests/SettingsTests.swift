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
}
