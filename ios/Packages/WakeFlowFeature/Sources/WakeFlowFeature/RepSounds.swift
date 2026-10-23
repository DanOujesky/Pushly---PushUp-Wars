import AVFoundation
import Core
import Foundation

/// Sound feedback during a rep session: a "pop" per counted rep, a soft thud for a rep that didn't count, a chime
/// when the target is reached, and the spoken count. Plays even with the silent switch on (it's a workout screen the
/// user opened); mixes with and ducks their music. Settings: `sounds.enabled` (master), `sounds.voice` (count aloud).
@MainActor
final class RepSounds {
    enum Effect: String {
        case count = "rep_count", miss = "rep_miss", done = "rep_done"
    }

    static let enabledKey = "sounds.enabled"
    static let voiceKey = "sounds.voice"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var voice: Bool {
        get { UserDefaults.standard.object(forKey: voiceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: voiceKey) }
    }

    private var players: [Effect: AVAudioPlayer] = [:]
    private let speech = AVSpeechSynthesizer()
    private var prepared = false

    func prepare() {
        guard !prepared else { return }
        prepared = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            PLog.error("Audio session failed: \(error)", .camera)
        }
        for effect in [Effect.count, .miss, .done] {
            guard let url = Bundle.module.url(forResource: effect.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[effect] = player
        }
    }

    func play(_ effect: Effect) {
        guard Self.enabled else { return }
        prepare()
        guard let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }

    func say(_ text: String) {
        guard Self.enabled, Self.voice else { return }
        prepare()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.55
        utterance.volume = 1
        speech.stopSpeaking(at: .immediate)
        speech.speak(utterance)
    }

    func stop() {
        speech.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        prepared = false
    }
}
