import Charts
import DesignSystem
import SwiftUI

/// The main part of Stats (D-067): what you're fighting for — trophies, league, the next step, your rank, the
/// players right above you, your record and how your trophies moved.
struct TrophySection: View {
    let stats: BattleStats
    let onFight: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.l) {
            hero
            if let onFight {
                PrimaryButton("Fight for trophies", action: onFight)
            }
            if !stats.targets.isEmpty { targets }
            record
            if stats.history.count > 1 {
                ChartCard(title: "Trophies", caption: "Last 60 days") { TrophyChart(points: stats.history) }
            }
            if !stats.recent.isEmpty { recent }
        }
    }

    private var hero: some View {
        Card {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                HStack(alignment: .center, spacing: SpacingTokens.m) {
                    Text(verbatim: BattleStats.glyph(stats.league)).font(.system(size: 52)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(stats.trophies) 🏆")
                            .typography(TypographyTokens.displayL)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                        Text(verbatim: BattleStats.leagueName(stats.league, stats.tier))
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.leagueGold))
                    }
                    Spacer()
                    if let rank = stats.rank {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: "#\(rank)").typography(TypographyTokens.stat)
                                .foregroundStyle(Color(ColorTokens.brandFlameText))
                            Text("in the world").typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                    }
                }
                GradientProgressBar(value: stats.progressToNext, height: 10)
                HStack {
                    if let next = stats.next {
                        Text("\(next.at - stats.trophies) 🏆 to \(BattleStats.leagueName(next.league, next.tier))")
                    } else {
                        Text("Top league reached")
                    }
                    Spacer()
                    if let days = stats.seasonDaysLeft() {
                        Text("Season ends in \(days) d")
                    }
                }
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                Text("Best ever: \(stats.bestTrophies) 🏆")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var targets: some View {
        Card {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Text("Next up on the ladder")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                ForEach(stats.targets) { t in
                    HStack(spacing: SpacingTokens.sm) {
                        AvatarView(username: t.username, presetID: t.avatarPreset, size: 32)
                        Text(verbatim: t.username).typography(TypographyTokens.bodyS)
                        Spacer()
                        Text(verbatim: "\(t.trophies) 🏆").typography(TypographyTokens.bodyS)
                        Text(verbatim: "+\(t.gap)")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.brandFlameText))
                    }
                    .frame(minHeight: TouchTarget.minimum)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(t.username), \(t.gap) trophies above you"))
                }
                Text("Win battles to pass them.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
    }

    private var record: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: SpacingTokens.m), GridItem(.flexible())], spacing: SpacingTokens.m) {
            StatTile(label: "Wins", value: "\(stats.record.wins)", delta: nil)
            StatTile(label: "Losses", value: "\(stats.record.losses)", delta: nil)
            StatTile(label: "Win rate", value: stats.record.winRate.map { "\($0) %" } ?? "–", delta: nil)
            StatTile(label: "Win streak", value: "\(stats.record.winStreak) 🔥 · best \(stats.record.bestWinStreak)", delta: nil)
        }
    }

    private var recent: some View {
        Card {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Text("Recent battles")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                ForEach(stats.recent) { b in
                    HStack {
                        Text(verbatim: b.result == "win" ? "W" : b.result == "loss" ? "L" : "D")
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(b.result == "win" ? ColorTokens.stateSuccessText
                                                   : b.result == "loss" ? ColorTokens.stateDanger : ColorTokens.textSecondary))
                            .frame(width: 24)
                        Text(verbatim: b.opponent).typography(TypographyTokens.bodyS)
                        Spacer()
                        if let d = b.delta, b.ranked {
                            Text(verbatim: d >= 0 ? "+\(d) 🏆" : "\(d) 🏆")
                                .typography(TypographyTokens.bodyS)
                                .foregroundStyle(Color(d >= 0 ? ColorTokens.stateSuccessText : ColorTokens.stateDanger))
                        } else {
                            Text("friendly").typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                    }
                    .frame(minHeight: TouchTarget.minimum)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Trophy balance over time (step line).
struct TrophyChart: View {
    let points: [BattleStats.Point]

    private var dated: [(date: Date, trophies: Int)] {
        let f = ISO8601DateFormatter()
        var out: [(date: Date, trophies: Int)] = points.compactMap { p in f.date(from: p.at).map { (date: $0, trophies: p.trophies) } }
        if let last = out.last { out.append((date: Date(), trophies: last.trophies)) }
        return out
    }

    var body: some View {
        Chart(dated, id: \.date) { p in
            LineMark(x: .value("Date", p.date), y: .value("Trophies", p.trophies))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color(ColorTokens.leagueGold))
            AreaMark(x: .value("Date", p.date), y: .value("Trophies", p.trophies))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(LinearGradient(colors: [Color(ColorTokens.leagueGold).opacity(0.35), .clear],
                                                startPoint: .top, endPoint: .bottom))
        }
        .frame(height: 180)
        .accessibilityLabel(Text("Trophies from \(points.first?.trophies ?? 0) to \(points.last?.trophies ?? 0)"))
    }
}
