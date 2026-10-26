import DesignSystem
import SwiftUI

/// All achievements by group (doc 10 §4): unlocked ones in their tier colour, locked ones dimmed with a lock.
public struct AchievementsView: View {
    let model: StatsModel

    public init(model: StatsModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.l) {
                ScreenTitle("Achievements", token: TypographyTokens.displayM)
                AchievementsGrid(model: model)
            }
            .padding(.horizontal, SpacingTokens.l)
            .padding(.bottom, SpacingTokens.xl)
        }
        .arenaBackground(glow: ColorTokens.leagueGold, alignment: .top, offset: CGSize(width: 0, height: -260))
        .task { if model.achievements.isEmpty { await model.loadAchievements() } }
    }
}

/// Progress header + every badge by group (unlocked first within a group).
struct AchievementsGrid: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.l) {
            if model.achievements.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let unlocked = model.achievements.filter(\.unlocked).count
                Card {
                    VStack(alignment: .leading, spacing: SpacingTokens.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "\(unlocked)").typography(TypographyTokens.displayM)
                                .foregroundStyle(Color(ColorTokens.leagueGold))
                            Text(verbatim: "/ \(model.achievements.count)").typography(TypographyTokens.titleM)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                            Spacer()
                            Text("unlocked").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textSecondary))
                        }
                        GradientProgressBar(value: Double(unlocked) / Double(max(model.achievements.count, 1)), height: 10)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(model.achievementGroups) { group in
                SectionLabel(LocalizedStringKey(group.group.capitalized))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: SpacingTokens.m)], spacing: SpacingTokens.m) {
                    ForEach(group.items.filter(\.unlocked) + group.items.filter { !$0.unlocked }) { AchievementBadge(item: $0) }
                }
            }
        }
    }
}

struct AchievementBadge: View {
    let item: AchievementItem

    var body: some View {
        VStack(spacing: SpacingTokens.s) {
            ZStack {
                Circle()
                    .fill(item.unlocked ? StatsPalette.tier(item.tier).opacity(0.18) : Color(ColorTokens.bgElevated))
                    .overlay(Circle().stroke(item.unlocked ? StatsPalette.tier(item.tier) : Color(ColorTokens.strokeSubtle),
                                             lineWidth: 2))
                Image(systemName: item.unlocked ? item.icon : "lock.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(item.unlocked ? StatsPalette.tier(item.tier) : Color(ColorTokens.textDisabled))
            }
            .frame(width: 64, height: 64)
            Text(verbatim: item.title)
                .typography(TypographyTokens.bodyS)
                .fontWeight(.semibold)
                .foregroundStyle(Color(item.unlocked ? ColorTokens.textPrimary : ColorTokens.textSecondary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(verbatim: item.description)
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(SpacingTokens.sm)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .top)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(item.unlocked ? "Unlocked" : "Locked"))
    }
}
