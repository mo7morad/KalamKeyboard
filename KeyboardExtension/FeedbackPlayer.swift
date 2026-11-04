import AudioToolbox
import UIKit

/// SPEC 5.3: a light haptic and a system click on touch-down. No AVAudioPlayer or audio session.
final class FeedbackPlayer {
    enum Sound: SystemSoundID {
        case key = 1104, delete = 1155, modifier = 1156
    }

    private let generator = UIImpactFeedbackGenerator(style: .light)
    private let settings: KeyboardSettings

    init(settings: KeyboardSettings) {
        self.settings = settings
    }

    func prepare() {
        if settings.haptics { generator.prepare() }
    }

    func touchDown(_ sound: Sound) {
        if settings.haptics {
            generator.impactOccurred(intensity: settings.hapticStrength)
            generator.prepare()
        }
        play(sound)
    }

    /// Sound only, for backspace repeats.
    func play(_ sound: Sound) {
        if settings.sounds { AudioServicesPlaySystemSound(sound.rawValue) }
    }
}
