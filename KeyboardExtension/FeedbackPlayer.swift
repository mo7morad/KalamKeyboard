import AudioToolbox
import KalamEngine
import os
import UIKit

/// SPEC 5.3: a rigid haptic and Apple's key sound, made louder, on touch-down. No AVAudioPlayer or
/// audio session: system sounds follow the ringer volume and the silent switch.
final class FeedbackPlayer {
    enum Sound: CaseIterable {
        case key, delete, modifier

        var resource: String {
            switch self {
            case .key: "key_press_click"
            case .delete: "key_press_delete"
            case .modifier: "key_press_modifier"
            }
        }

        /// Apple's own sound, if the bundled one fails to load.
        var systemID: SystemSoundID {
            switch self {
            case .key: 1104
            case .delete: 1155
            case .modifier: 1156
            }
        }
    }

    private static let log = Logger(subsystem: "com.morad.kalam.keyboard", category: "feedback")

    private let generator = UIImpactFeedbackGenerator(style: .rigid)
    private let soundIDs: [Sound: SystemSoundID]
    var settings = Settings()

    init() {
        soundIDs = Dictionary(uniqueKeysWithValues: Sound.allCases.map { ($0, Self.register($0)) })
    }

    deinit {
        for (sound, id) in soundIDs where id != sound.systemID { AudioServicesDisposeSystemSoundID(id) }
    }

    private static func register(_ sound: Sound) -> SystemSoundID {
        var id: SystemSoundID = 0
        guard let url = Bundle.main.url(forResource: sound.resource, withExtension: "caf"),
              AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else {
            log.error("\(sound.resource, privacy: .public).caf didn't load; using system sound \(sound.systemID)")
            return sound.systemID
        }
        return id
    }

    func prepare() {
        if settings.haptics { generator.prepare() }
    }

    func touchDown(_ sound: Sound) {
        if settings.haptics {
            generator.impactOccurred(intensity: CGFloat(settings.hapticStrength))
            generator.prepare()
        }
        play(sound)
    }

    /// Sound only, for backspace repeats.
    func play(_ sound: Sound) {
        if settings.sounds { AudioServicesPlaySystemSound(soundIDs[sound, default: sound.systemID]) }
    }
}
