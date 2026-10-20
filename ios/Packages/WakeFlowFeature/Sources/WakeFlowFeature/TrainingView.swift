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
    @AppStorage("training.speakCount") private var speak = false

    public init(services: SessionServices? = nil, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.services = services
        _model = State(initialValue: RepSessionModel(mode: .training) { _ in })
    }

    public var body: some View {
        if let summary {
            TrainingSummaryView(summary: summary, onDone: onClose)
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
                        if model.counted > 0, let services { _ = services.submitTraining(model, anchor: anchor) }
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
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.l) {
            Spacer()
            SectionLabel("Training done", color: ColorTokens.brandFlameText)
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
            let rejectedTotal = summary.rejected.values.reduce(0, +)
            if rejectedTotal > 0, let top = summary.rejected.max(by: { $0.value < $1.value })?.key {
                InlineBanner(LocalizedStringKey("\(rejectedTotal) reps didn't count. Most often: \(RepText.hint(top))"), kind: .info)
            }
            Spacer()
            PrimaryButton("Done", action: onDone)
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandFlame, alignment: .top, offset: CGSize(width: 0, height: -200))
    }
}
