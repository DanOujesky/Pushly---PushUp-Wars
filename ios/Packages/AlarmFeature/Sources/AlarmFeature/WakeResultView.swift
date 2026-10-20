import AlarmDomain
import DesignSystem
import SwiftUI
import WakeFlowFeature

/// Completion (PS-32) and failure (PS-33) after a wake challenge. Shows the provisional result at once and the
/// server's validated numbers when they arrive (PS-90: "pending" until then). No ads here (CLAUDE.md §4.5).
struct WakeResultView: View {
    let challenge: WakeChallengeModel
    let onDone: () -> Void

    private var serverWake: SessionResult.Wake? { challenge.result?.wake }
    private var succeeded: Bool {
        if let status = serverWake?.status, status != "not_challenge" { return status == "succeeded" }
        return challenge.decision?.status == "succeeded"
    }

    var body: some View {
        let summary = challenge.reps.summary
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            Spacer()
            SectionLabel(succeeded ? "Challenge beaten" : "Challenge lost today",
                         color: succeeded ? ColorTokens.stateSuccessText : ColorTokens.textSecondary)
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
            if succeeded {
                validated
            } else {
                Text(failureText)
                    .typography(TypographyTokens.body)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                if serverWake?.status == "failed", let streak = challenge.result?.streak, streak.current > 0 {
                    InlineBanner("A streak freeze saved your \(streak.current)-day streak.", kind: .info)
                }
                Text("Try a Train now session later?")
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            Spacer()
            PrimaryButton("Done", action: onDone)
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: succeeded ? ColorTokens.stateSuccess : ColorTokens.brandFlame, alignment: .top,
                         offset: CGSize(width: 0, height: -200))
    }

    @ViewBuilder
    private var validated: some View {
        if let result = challenge.result {
            HStack(spacing: SpacingTokens.s) {
                if let points = result.wake?.points, points > 0 {
                    Pill("+\(points) wake points", color: ColorTokens.brandFlameText)
                }
                Pill("🔥 \(result.streak.current) day streak")
            }
            if !result.verified {
                InlineBanner("This session couldn't be verified, so it only counts for your personal stats.", kind: .warning)
            }
        } else {
            HStack(spacing: SpacingTokens.s) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(challenge.pending ? "Verifying with the server…" : "Will be verified when you're online.")
                    .typography(TypographyTokens.bodyS)
            }
            .foregroundStyle(Color(ColorTokens.textTertiary))
            .accessibilityElement(children: .combine)
        }
    }

    private var failureText: String {
        switch serverWake?.reason ?? challenge.decision?.reason {
        case "window_expired": String(localized: "The clock beat you this time — the push-ups came after the window.")
        case "sprint_too_few": String(localized: "Not enough push-ups in the sprint window.")
        case "rest_too_long": String(localized: "The next set started too late after the rest.")
        default: String(localized: "No worries — tomorrow is a new chance.")
        }
    }
}
