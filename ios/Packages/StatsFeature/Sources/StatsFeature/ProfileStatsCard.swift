import DesignSystem
import SwiftUI

/// Profile tab (D-077): your numbers at a glance — level and XP, trophies and league, battle record, push-ups — a
/// 7-day bar strip and achievements progress. Every part opens the full Stats screen on the right section.
public struct ProfileStatsCard: View {
    @State private var model: StatsModel
    private let onFight: (() -> Void)?

    public init(model: StatsModel, onFight: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onFight = onFight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            if let stats = model.stats { level(stats.progress) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SpacingTokens.s), GridItem(.flexible())], spacing: SpacingTokens.s) {
                link(.battles) {
                    tile("🏆", value: model.battle.map { "\($0.trophies)" } ?? "–",
                         label: model.battle.map { BattleStats.leagueName($0.league, $0.tier) } ?? String(localized: "Trophies"),
                         tint: ColorTokens.leagueGold)
                }
                link(.battles) {
                    tile("⚔️", value: model.battle?.record.winRate.map { "\($0)%" } ?? "–",
                         label: model.battle.map { String(localized: "\($0.record.wins) W · \($0.record.losses) L") }
                             ?? String(localized: "Win rate"),
                         tint: ColorTokens.stateSuccessText)
                }
                link(.pushups) {
                    tile("💪", value: model.stats.map { "\($0.records.repsAllTime)" } ?? "–",
                         label: String(localized: "Push-ups all time"), tint: ColorTokens.brandFlameText)
                }
                link(.pushups) {
                    tile("⭐", value: model.stats.map { "\($0.records.bestSet)" } ?? "–",
                         label: String(localized: "Best set"), tint: ColorTokens.brandVoltText)
                }
            }
            if let stats = model.stats {
                link(.pushups) { week(stats) }
                link(.badges) { badges(stats.achievements) }
            } else if model.failed {
                InlineBanner("Stats couldn't load. Pull down to try again.", kind: .warning)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .task {
            if model.battle == nil { await model.loadBattle() }
            if model.stats == nil { await model.load() }
            if model.achievements.isEmpty { await model.loadAchievements() }
        }
    }

    private func link<Label: View>(_ section: StatsView.Section, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            StatsView(model: model, onFight: onFight, section: section)
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func level(_ level: StatsData.Level) -> some View {
        HStack(spacing: SpacingTokens.m) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle().trim(from: 0, to: level.fraction)
                    .stroke(Color(ColorTokens.brandVolt), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: "\(level.level)").typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textPrimary))
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Level \(level.level)").typography(TypographyTokens.titleM).foregroundStyle(Color(ColorTokens.textPrimary))
                GradientProgressBar(value: level.fraction, height: 8)
                Text("\(level.xpForNext - level.xpIntoLevel) XP to level \(level.level + 1)")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tile(_ glyph: String, value: String, label: String, tint: TokenColor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: glyph).font(.title3).accessibilityHidden(true)
            Text(verbatim: value)
                .typography(TypographyTokens.stat)
                .foregroundStyle(Color(tint))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: label)
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(SpacingTokens.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(tint).opacity(0.14), Color(ColorTokens.bgSurface)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .accessibilityElement(children: .combine)
    }

    private func week(_ stats: StatsData) -> some View {
        let days = StatsSeries.lastDays(stats)
        let top = max(days.map(\.total).max() ?? 0, 1)
        let total = days.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: SpacingTokens.s) {
            HStack {
                Text("Last 7 days").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                Spacer()
                Text("\(total) push-ups").typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.brandFlameText))
            }
            HStack(alignment: .bottom, spacing: SpacingTokens.s) {
                ForEach(days, id: \.day) { d in
                    VStack(spacing: 4) {
                        Text(verbatim: d.total > 0 ? "\(d.total)" : "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(d.total > 0 ? AnyShapeStyle(LinearGradient(GradientTokens.hero)) : AnyShapeStyle(Color.white.opacity(0.08)))
                            .frame(height: max(6, 70 * CGFloat(d.total) / CGFloat(top)))
                        Text(verbatim: Self.weekday(d.day))
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(d.day == stats.to ? ColorTokens.textPrimary : ColorTokens.textTertiary))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last 7 days: \(total) push-ups"))
    }

    static func weekday(_ day: String) -> String {
        guard let d = StatsSeries.date(day) else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let symbols = cal.veryShortWeekdaySymbols
        return symbols[(cal.component(.weekday, from: d) - 1) % symbols.count]
    }

    private func badges(_ count: StatsData.AchievementCount) -> some View {
        let recent = model.achievements.filter(\.unlocked).sorted { ($0.unlockedAt ?? "") > ($1.unlockedAt ?? "") }.prefix(4)
        return HStack(spacing: SpacingTokens.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Achievements").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                GradientProgressBar(value: count.total == 0 ? 0 : Double(count.unlocked) / Double(count.total), height: 8)
                Text(verbatim: "\(count.unlocked) / \(count.total)").typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            HStack(spacing: -6) {
                ForEach(Array(recent)) { a in
                    Image(systemName: a.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StatsPalette.tier(a.tier))
                        .frame(width: 34, height: 34)
                        .background(Color(ColorTokens.bgElevated), in: Circle())
                        .overlay(Circle().strokeBorder(StatsPalette.tier(a.tier), lineWidth: 1.5))
                }
            }
            .accessibilityHidden(true)
            Image(systemName: "chevron.right").foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
