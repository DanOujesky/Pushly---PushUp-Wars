import AlarmDomain
import AVFoundation
import Core
import DesignSystem
import SwiftUI
import WakeFlowFeature

/// Wake session (doc 04 §3, PS-30…PS-34): the camera counts the push-ups under the mode rules
/// (`WakeChallengeModel`); when it is over the result screen shows the provisional result and then the server's.
/// While it is open the app plays the alarm sound quietly and keeps the dead-man's switch nag 90 s ahead
/// (doc 04 §5.2). Debug builds keep a "Complete" button for testing without a camera; it is compiled out of release
/// builds (CLAUDE.md §10).
public struct WakeSessionView: View {
    let model: WakeModel
    let ring: RingState
    @State private var sound = AlarmSoundLoop()
    @State private var confirmGiveUp = false
    @State private var challenge: WakeChallengeModel
    @State private var over = false

    public init(model: WakeModel, ring: RingState) {
        self.model = model
        self.ring = ring
        _challenge = State(initialValue: WakeChallengeModel(ring: ring, services: model.services))
    }

    public var body: some View {
        Group {
            if over {
                WakeResultView(challenge: challenge) {
                    Task { await model.closeSession() }
                }
            } else {
                camera
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            AppActivity.wakeStarted()   // no ads during the wake flow and for 10 minutes after it (CLAUDE.md §4.5)
            challenge.onOver = { succeeded in
                sound.stop()
                over = true
                Task { await model.challengeOver(ring, succeeded: succeeded) }
            }
            challenge.onRestOver = { sound.start(AlarmSounds.resourceName(ring.soundId), volume: 1) }
            challenge.reps.prewarm()
            challenge.start()
        }
        .task {
            sound.start(AlarmSounds.resourceName(ring.soundId), volume: 0.3)
            // Dead-man's switch: keep the next nag 90 s ahead while this screen is alive.
            while !Task.isCancelled, !over {
                try? await Task.sleep(for: .seconds(60))
                await model.heartbeat()
            }
        }
        .onDisappear {
            AppActivity.wakeEnded()
            sound.stop()
            challenge.stop()
        }
    }

    private var camera: some View {
        RepSessionView(model: challenge.reps) {
            VStack(spacing: SpacingTokens.s) {
                if let ends = ring.beatTheClockEndsAt {
                    BeatTheClockBanner(endsAt: ends)
                }
                #if DEBUG
                SecondaryButton("Complete (debug build only)") {
                    sound.stop()
                    Task { await model.completeSession() }
                }
                #endif
                HStack(spacing: SpacingTokens.s) {
                    if ring.canSnooze {
                        GhostButton("Snooze +\(ring.mode.snoozeAddsReps ?? 0)") {
                            sound.stop()
                            Task { await model.snooze() }
                        }
                    }
                    GhostButton("Back to the alarm") {
                        sound.stop()
                        Task { await model.leaveSession() }
                    }
                    Spacer()
                    GhostButton("Give up") { confirmGiveUp = true }
                }
            }
        }
        .confirmationDialog("Give up this morning's challenge?", isPresented: $confirmGiveUp, titleVisibility: .visible) {
            Button("Give up", role: .destructive) { challenge.giveUp() }
        } message: {
            Text("The alarm stops and today counts as failed.")
        }
    }
}

struct BeatTheClockBanner: View {
    let endsAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(Int(endsAt.timeIntervalSince(context.date)), 0)
            InlineBanner(left > 0 ? "Beat the clock: \(left / 60):\(String(format: "%02d", left % 60)) left"
                : "The window is over — finish your push-ups to stop the alarm.", kind: left > 0 ? .warning : .error)
        }
    }
}

/// Loops the alarm sound in the app while the wake session is open (doc 04 §5.2 step 3).
@MainActor
final class AlarmSoundLoop {
    private var player: AVAudioPlayer?

    func start(_ name: String, volume: Float) {
        guard player == nil, let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = volume
            p.play()
            player = p
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
