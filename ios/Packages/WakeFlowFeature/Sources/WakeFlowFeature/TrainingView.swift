import DesignSystem
import RepEngine
import SwiftUI

/// Free training (PS-80): count push-ups with the camera, no target. Uploaded as a training session (totals and
/// personal stats, never the wake streak) when a backend is available.
public struct TrainingView: View {
    let onClose: () -> Void
    let services: SessionServices?
    @State private var model: RepSessionModel
    @State private var summary: RepSessionModel.Summary?
    @State private var anchor: ServerAnchor?
    @State private var sessionId: String?
    @AppStorage("sounds.voice") private var speak = true

    public init(services: SessionServices? = nil, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.services = services
        _model = State(initialValue: RepSessionModel(mode: .training) { _ in })
    }

    public var body: some View {
        if let summary {
            TrainingSummaryView(summary: summary, result: sessionId.flatMap { services?.uploader.results[$0] },
                                pending: sessionId.map { services?.uploader.isPending(sessionId: $0) ?? false } ?? false,
                                frontReps: model.frontReps, onDone: onClose)
        } else {
            RepSessionView(model: model) {
                HStack(spacing: SpacingTokens.s) {
                    GhostButton(speak ? "Voice on" : "Voice off") {
                        speak.toggle()
                        model.speakCount = speak
                    }
                    Spacer()
                    PrimaryButton("End") {
                        model.finish()
                        summary = model.summary
                        if model.counted > 0, let services { sessionId = services.submitTraining(model, anchor: anchor) }
                    }
                    .frame(maxWidth: 160)
                }
            }
            .onAppear { model.speakCount = speak }
            .task { anchor = await services?.anchor() }
        }
    }
}

struct TrainingSummaryView: View {
    let summary: RepSessionModel.Summary
    var result: SessionResult?
    var pending = false
    /// Set by a workout (D-069): its name and the result of every set.
    var workout: Workout?
    var sets: [WorkoutRunner.SetResult] = []
    /// Push-ups counted from the front: the session is personal only (D-064) — said loudly (D-070).
    var frontReps = 0
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    content
                }
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .leading)
                .padding(.top, SpacingTokens.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            PrimaryButton("Done", action: onDone)
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandFlame, alignment: .top, offset: CGSize(width: 0, height: -200))
    }

    @ViewBuilder private var content: some View {
        if let workout {
            SectionLabel("Workout done", color: ColorTokens.brandFlameText)
            Text(verbatim: workout.name)
                .typography(TypographyTokens.titleM)
                .foregroundStyle(Color(ColorTokens.textPrimary))
        } else {
            SectionLabel("Training done", color: ColorTokens.brandFlameText)
        }
        Text(verbatim: "\(summary.reps)")
            .typography(TypographyTokens.displayCounter)
            .foregroundStyle(Color(ColorTokens.textPrimary))
        Text("push-ups")
            .typography(TypographyTokens.labelDisplay)
            .foregroundStyle(Color(ColorTokens.textTertiary))
        HStack(spacing: SpacingTokens.s) {
            Pill("Form \(summary.averageQuality)", color: ColorTokens.stateSuccessText)
            Pill("\(summary.durationSeconds / 60) min \(summary.durationSeconds % 60) s")
        }
        if frontReps > 0 {
            InlineBanner("Filmed from the front: these push-ups count for your stats and alarm — not for battles or your clan's Clan War. Put the phone at your side next time.",
                         kind: .warning)
        } else if summary.reps > 0 {
            InlineBanner("Filmed from the side ✓ — once verified, these push-ups count for the leaderboards and your clan's Clan War.", kind: .success)
        }
        if let workout, !sets.isEmpty { WorkoutSetResults(workout: workout, sets: sets) }
        let rejectedTotal = summary.rejected.values.reduce(0, +)
        if rejectedTotal > 0, let top = summary.rejected.max(by: { $0.value < $1.value })?.key {
            InlineBanner(LocalizedStringKey("\(rejectedTotal) reps didn't count. Most often: \(RepText.hint(top))"), kind: .info)
        }
        if let result {
            SessionRewardsView(result: result)
        } else if pending {
            Text("Adding XP when the server confirms…")
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textTertiary))
        }
    }
}
