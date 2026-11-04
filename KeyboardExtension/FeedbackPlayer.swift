import AudioToolbox
import Foundation
import KalamEngine
import os
import UIKit

/// SPEC 5.3: a rigid haptic and Apple's key sound on touch-down. No AVAudioPlayer or audio session:
/// system sounds follow the ringer volume and the silent switch.
final class FeedbackPlayer {
    enum Sound: CaseIterable {
        case key, delete, modifier

        /// Apple's own sound, bundled as 16-bit WAV for the boosted copies.
        var resource: String {
            switch self {
            case .key: "key_press_click"
            case .delete: "key_press_delete"
            case .modifier: "key_press_modifier"
            }
        }

        var systemID: SystemSoundID {
            switch self {
            case .key: 1104
            case .delete: 1155
            case .modifier: 1156
            }
        }
    }

    /// `soundBoost` just above 0 plays the copies this quiet, and 1 this loud (dB on the files, whose
    /// peak is near -8.5 dBFS). A registered sound plays much louder than the system ID's keyboard
    /// click at the same file level, so the range starts well below 0 dB (device round 2).
    private static let boostRangeDB = -30.0...7.5
    private static let log = Logger(subsystem: "com.morad.kalam.keyboard", category: "feedback")

    private let generator = UIImpactFeedbackGenerator(style: .rigid)
    /// Boosted copies; empty at boost 0, where the system IDs play.
    private var soundIDs: [Sound: SystemSoundID] = [:]
    var settings = Settings() {
        didSet { if settings.soundBoost != oldValue.soundBoost { registerSounds() } }
    }

    deinit { disposeSounds() }

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

    private func registerSounds() {
        disposeSounds()
        guard settings.soundBoost > 0 else { return }
        let range = Self.boostRangeDB
        let gain = pow(10, (range.lowerBound + settings.soundBoost * (range.upperBound - range.lowerBound)) / 20)
        for sound in Sound.allCases {
            var id: SystemSoundID = 0
            guard let url = Self.boosted(sound, gain: gain),
                  AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else {
                Self.log.error("boosted \(sound.resource, privacy: .public) didn't load; using system sound \(sound.systemID)")
                continue
            }
            soundIDs[sound] = id
        }
    }

    private func disposeSounds() {
        soundIDs.values.forEach { AudioServicesDisposeSystemSoundID($0) }
        soundIDs = [:]
    }

    /// Writes the bundled WAV with its 16-bit samples scaled by `gain` (clipped) to the temp folder,
    /// named by gain so a new level never reuses a file iOS may have cached.
    private static func boosted(_ sound: Sound, gain: Double) -> URL? {
        guard let source = Bundle.main.url(forResource: sound.resource, withExtension: "wav"),
              var data = try? Data(contentsOf: source),
              let chunk = data.range(of: Data("data".utf8)) else { return nil }
        let samples = chunk.upperBound + 4  // past the chunk size
        data.withUnsafeMutableBytes { bytes in
            for offset in stride(from: samples, to: bytes.count - 1, by: 2) {
                let sample = Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self)))
                bytes.storeBytes(of: Int16(clamping: Int((sample * gain).rounded())).littleEndian, toByteOffset: offset, as: Int16.self)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(sound.resource)-\(Int(gain * 1000)).wav")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            log.error("boosted \(sound.resource, privacy: .public) not written: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
