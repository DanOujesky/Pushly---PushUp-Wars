import DesignSystem
import SwiftUI

/// What a validated session earned (doc 10 §3–5): XP, level progress, a new best set and unlocked achievements.
/// Shown on the wake and training result screens once the server answered. Never shows an ad (CLAUDE.md §4.5).
public struct SessionRewardsView: View {
    let result: SessionResult
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(result: SessionResult) {
        self.result = result
    }

    public var body: some View {
        if let progress = result.progress {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                if result.newBestSet == true {
                    InlineBanner("New record: your best set ever!", kind: .success)
                }
                HStack(spacing: SpacingTokens.s) {
                    if progress.xpGained > 0 {
                        Pill("+\(progress.xpGained) XP", color: ColorTokens.brandVoltText)
                    }
                    Pill(progress.levelUp ? "Level up! Level \(progress.level)" : "Level \(progress.level)",
                         color: progress.levelUp ? ColorTokens.leagueGold : nil)
                }
                GradientProgressBar(value: appeared || reduceMotion
                                    ? Double(progress.xpIntoLevel) / Double(max(progress.xpForNext, 1)) : 0)
                    .animation(.easeOut(duration: MotionTokens.slowSeconds), value: appeared)
                ForEach(progress.newAchievements) { achievement in
                    UnlockedRow(achievement: achievement)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onAppear { appeared = true }
            .accessibilityElement(children: .contain)
        }
    }
}

struct UnlockedRow: View {
    let achievement: SessionResult.Progress.Unlocked

    var body: some View {
        HStack(spacing: SpacingTokens.m) {
            Image(systemName: achievement.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(ColorTokens.leagueGold))
                .frame(width: 44, height: 44)
                .background(Color(ColorTokens.leagueGold).opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement unlocked")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                Text(verbatim: achievement.title)
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text(verbatim: achievement.description)
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            Spacer(minLength: 0)
            if achievement.xp > 0 {
                Text(verbatim: "+\(achievement.xp) XP")
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.brandVoltText))
            }
        }
        .padding(SpacingTokens.sm)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .accessibilityElement(children: .combine)
    }
}
