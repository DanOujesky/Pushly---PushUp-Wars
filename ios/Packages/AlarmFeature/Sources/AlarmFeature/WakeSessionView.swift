import AlarmDomain
import AVFoundation
import DesignSystem
import SwiftUI

/// Wake session placeholder until the camera + rep engine arrive (Phase 3). While it is open the app plays the alarm
/// sound quietly and keeps the dead-man's switch nag 90 s ahead (doc 04 §5.2). Debug builds have a "Complete"
/// button; it is compiled out of release builds (CLAUDE.md §10).
public struct WakeSessionView: View {
    let model: WakeModel
    let ring: RingState
    @State private var sound = AlarmSoundLoop()
    @State private var confirmGiveUp = false

    public init(model: WakeModel, ring: RingState) {
        self.model = model
        self.ring = ring
    }

    public var body: some View {
        VStack(spacing: SpacingTokens.l) {
            ScrollView {
                VStack(spacing: SpacingTokens.m) {
                    SectionLabel(ring.practice ? "Practice alarm" : "Wake challenge", color: ColorTokens.brandFlameText)
                    Text(verbatim: "\(ring.target)")
                        .typography(TypographyTokens.displayCounter)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("push-ups to go")
                        .typography(TypographyTokens.labelDisplay)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                    Text(verbatim: ModeText.summary(ring.mode))
                        .typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                    if let ends = ring.beatTheClockEndsAt {
                        BeatTheClockBanner(endsAt: ends)
                    }
                    InlineBanner(
                        "Push-up counting with the camera arrives in the next update. Until then the alarm keeps ringing quietly while this screen is open.",
                        kind: .info
                    )
                        .padding(.top, SpacingTokens.m)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, SpacingTokens.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: SpacingTokens.sm) {
                #if DEBUG
                PrimaryButton("Complete (debug build only)") {
                    sound.stop()
                    Task { await model.completeSession() }
                }
                #endif
                if ring.canSnooze {
                    SecondaryButton("Snooze \(ring.mode.snoozeMinutes ?? 5) min (+\(ring.mode.snoozeAddsReps ?? 0) push-ups)") {
                        sound.stop()
                        Task { await model.snooze() }
                    }
                }
                SecondaryButton("Back to the alarm") {
                    sound.stop()
                    Task { await model.leaveSession() }
                }
                GhostButton("Give up") { confirmGiveUp = true }
            }
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .center)
        .interactiveDismissDisabled()
        .confirmationDialog("Give up this morning's challenge?", isPresented: $confirmGiveUp, titleVisibility: .visible) {
            Button("Give up", role: .destructive) {
                sound.stop()
                Task { await model.giveUp() }
            }
        } message: {
            Text("The alarm stops and today counts as failed.")
        }
        .task {
            sound.start(AlarmSounds.resourceName(ring.soundId), volume: 0.3)
            // Dead-man's switch: keep the next nag 90 s ahead while this screen is alive.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await model.heartbeat()
            }
        }
        .onDisappear { sound.stop() }
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
