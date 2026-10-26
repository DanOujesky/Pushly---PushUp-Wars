import DesignSystem
import SwiftUI

/// Battle history (D-077): a record card (win rate, last 10, streak, close calls, trophies) and every battle as a match
/// card — VICTORY / DEFEAT, the final score face to face, by how much it was decided ("Lost by 1 push-up") and a
/// SO CLOSE / CLUTCH tag for nail-biters. Grouped by day. Past seasons at the end.
struct HistorySheet: View {
    let model: BattleHubModel
    let player: BattlePlayer?
    @Environment(\.dismiss) private var dismiss

    private var groups: [(day: String, battles: [Battle])] {
        var out: [(day: String, battles: [Battle])] = []
        for b in model.history {
            let label = HistoryDates.dayLabel(b.endedAt ?? b.createdAt)
            if let last = out.last, last.day == label {
                out[out.count - 1].battles.append(b)
            } else {
                out.append((day: label, battles: [b]))
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SpacingTokens.m) {
                    RecordCard(summary: HistorySummary(model.history), record: model.arena?.record)
                    if model.history.isEmpty {
                        VStack(spacing: SpacingTokens.s) {
                            Text(verbatim: "⚔️").font(.system(size: 44)).accessibilityHidden(true)
                            Text("No battles yet").typography(TypographyTokens.titleM)
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                            Text("Your battles show up here — every win, every loss and every close call.")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textSecondary))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingTokens.xl)
                    }
                    ForEach(groups, id: \.day) { group in
                        SectionLabel(LocalizedStringKey(group.day))
                            .padding(.top, SpacingTokens.s)
                        ForEach(group.battles) { b in
                            MatchCard(battle: b, recap: BattleRecap(b), player: player)
                        }
                    }
                    if !model.seasons.isEmpty {
                        SectionLabel("Past seasons").padding(.top, SpacingTokens.m)
                        ScrollView(.horizontal) {
                            HStack(spacing: SpacingTokens.sm) {
                                ForEach(model.seasons) { SeasonCard(season: $0) }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, SpacingTokens.m)
                .padding(.bottom, SpacingTokens.xl)
            }
            .background(Color(ColorTokens.bgBase).ignoresSafeArea())
            .navigationTitle(Text("Battle history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

enum HistoryDates {
    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let trimmed = iso.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }

    static func dayLabel(_ iso: String?) -> String {
        guard let d = date(iso) else { return String(localized: "Earlier") }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "Today") }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday") }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func time(_ iso: String?) -> String? {
        date(iso).map { $0.formatted(date: .omitted, time: .shortened) }
    }
}

private func outcomeColor(_ o: BattleRecap.Outcome) -> TokenColor {
    switch o {
    case .win: ColorTokens.stateSuccessText
    case .loss: ColorTokens.stateDanger
    case .draw: ColorTokens.textSecondary
    }
}

/// Win rate ring, W–L–D, last 10, streak and the close-call counters.
struct RecordCard: View {
    let summary: HistorySummary
    let record: ArenaStatus.Record?

    private var wins: Int { record?.wins ?? summary.wins }
    private var losses: Int { record?.losses ?? summary.losses }
    private var draws: Int { record?.draws ?? summary.draws }
    private var played: Int { wins + losses + draws }
    private var rate: Double { played == 0 ? 0 : Double(wins) / Double(played) }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            HStack(spacing: SpacingTokens.l) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: rate)
                        .stroke(LinearGradient(GradientTokens.success), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(verbatim: played == 0 ? "–" : "\(Int((rate * 100).rounded()))%")
                            .typography(TypographyTokens.titleL)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                        Text("win rate").typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: SpacingTokens.s) {
                    HStack(spacing: SpacingTokens.m) {
                        tally(wins, "W", ColorTokens.stateSuccessText)
                        tally(losses, "L", ColorTokens.stateDanger)
                        tally(draws, "D", ColorTokens.textSecondary)
                    }
                    if !summary.form.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last \(summary.form.count)").typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                            HStack(spacing: 4) {
                                // oldest → newest, newest on the right
                                ForEach(Array(summary.form.reversed().enumerated()), id: \.offset) { _, o in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(outcomeColor(o)))
                                        .frame(width: 14, height: 14)
                                        .overlay {
                                            Text(verbatim: o == .win ? "W" : o == .loss ? "L" : "D")
                                                .font(.system(size: 8, weight: .heavy))
                                                .foregroundStyle(.black.opacity(0.6))
                                        }
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: SpacingTokens.s) {
                if let r = record, r.winStreak > 1 { chip("🔥 \(r.winStreak) win streak", ColorTokens.brandFlameText) }
                if let r = record, r.bestWinStreak > 0 { chip("Best streak \(r.bestWinStreak)", ColorTokens.textSecondary) }
            }
            HStack(spacing: SpacingTokens.s) {
                if summary.clutchWins > 0 { chip("⚡ \(summary.clutchWins) clutch wins", ColorTokens.brandVoltText) }
                if summary.closeLosses > 0 { chip("😤 \(summary.closeLosses) so close", ColorTokens.stateWarning) }
                if summary.trophyNet != 0 {
                    chip(LocalizedStringKey(summary.trophyNet > 0 ? "+\(summary.trophyNet) 🏆 recently" : "\(summary.trophyNet) 🏆 recently"),
                         summary.trophyNet > 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger)
                }
            }
        }
        .padding(SpacingTokens.ml)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(ColorTokens.brandFlame).opacity(0.18), Color(ColorTokens.bgSurface)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .accessibilityElement(children: .combine)
    }

    private func tally(_ n: Int, _ letter: String, _ color: TokenColor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(n)").typography(TypographyTokens.stat).foregroundStyle(Color(color))
            Text(verbatim: letter).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
        }
    }

    private func chip(_ text: LocalizedStringKey, _ color: TokenColor) -> some View {
        Pill(text, color: color)
    }
}

/// One battle: outcome banner, the score face to face, how it was decided.
struct MatchCard: View {
    let battle: Battle
    let recap: BattleRecap
    let player: BattlePlayer?

    private var tint: Color { Color(outcomeColor(recap.outcome)) }

    private var title: LocalizedStringKey {
        if battle.status == "void" { return "NO RESULT" }
        switch recap.outcome {
        case .win: return "VICTORY"
        case .loss: return "DEFEAT"
        case .draw: return "DRAW"
        }
    }

    private var closeTag: LocalizedStringKey? {
        guard recap.isClose else { return nil }
        switch recap.outcome {
        case .win: return "⚡ CLUTCH"
        case .loss: return "😤 SO CLOSE"
        case .draw: return "🤝 DEAD EVEN"
        }
    }

    private var kind: LocalizedStringKey {
        if battle.bot == "arena" { return "Arena Bot · ranked" }
        if battle.bot != nil { return "Practice" }
        if battle.ranked { return "Ranked" }
        return "Friendly"
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(tint).frame(width: 5)
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                HStack(spacing: SpacingTokens.s) {
                    Text(title)
                        .typography(TypographyTokens.labelDisplay)
                        .foregroundStyle(tint)
                    if let closeTag {
                        Text(closeTag)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color(ColorTokens.bgBase))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(recap.outcome == .loss ? ColorTokens.stateWarning : ColorTokens.brandVolt), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if let time = HistoryDates.time(battle.endedAt ?? battle.createdAt) {
                        Text(verbatim: time).typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                }
                HStack(spacing: SpacingTokens.s) {
                    side(name: String(localized: "You"), preset: player?.avatarPreset, username: player?.username ?? "?",
                         score: recap.mine, lead: recap.mine >= recap.theirs, alignment: .leading)
                    Text(verbatim: "–").typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textTertiary))
                    side(name: battle.opponentDisplayName, preset: battle.opponent.avatarPreset, username: battle.opponent.username,
                         score: recap.theirs, lead: recap.theirs >= recap.mine, alignment: .trailing)
                }
                HStack(spacing: SpacingTokens.s) {
                    Text(verbatim: recap.line)
                        .typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    Spacer(minLength: 0)
                    if let t = battle.myTrophies, battle.ranked {
                        Pill(LocalizedStringKey(t >= 0 ? "+\(t) 🏆" : "\(t) 🏆"), color: t >= 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger)
                    }
                }
                Text("\(modeTitle(battle.mode, battle.variant)) · \(Text(kind))")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            .padding(SpacingTokens.m)
        }
        .background(
            LinearGradient(colors: [tint.opacity(recap.isClose ? 0.16 : 0.10), Color(ColorTokens.bgSurface)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
            .strokeBorder(recap.isClose ? tint.opacity(0.5) : Color(ColorTokens.strokeSubtle)))
        .accessibilityElement(children: .combine)
    }

    private func side(name: String, preset: String?, username: String, score: Int, lead: Bool,
                      alignment: HorizontalAlignment) -> some View {
        HStack(spacing: SpacingTokens.s) {
            if alignment == .trailing { Spacer(minLength: 0) }
            if alignment == .trailing {
                scoreText(score, lead: lead)
                VStack(alignment: .trailing, spacing: 2) { avatar(username, preset); label(name) }
            } else {
                VStack(alignment: .leading, spacing: 2) { avatar(username, preset); label(name) }
                scoreText(score, lead: lead)
            }
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatar(_ username: String, _ preset: String?) -> some View {
        AvatarView(username: username, presetID: preset, size: 34)
    }

    private func label(_ name: String) -> some View {
        Text(verbatim: name)
            .typography(TypographyTokens.caption)
            .foregroundStyle(Color(ColorTokens.textSecondary))
            .lineLimit(1)
            .frame(maxWidth: 110, alignment: .leading)
    }

    private func scoreText(_ n: Int, lead: Bool) -> some View {
        Text(verbatim: "\(n)")
            .typography(TypographyTokens.displayM)
            .monospacedDigit()
            .foregroundStyle(Color(lead ? ColorTokens.textPrimary : ColorTokens.textTertiary))
    }
}

struct SeasonCard: View {
    let season: SeasonResult

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text(verbatim: leagueGlyph(season.league)).font(.system(size: 34)).accessibilityHidden(true)
            Text(verbatim: season.month).typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
            Text(verbatim: leagueTitle(season.league, season.tier)).typography(TypographyTokens.caption)
                .foregroundStyle(Color(leagueColor(season.league)))
            Text("Best \(season.bestTrophies) 🏆 · #\(season.rank)").typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
        }
        .padding(SpacingTokens.m)
        .frame(width: 150, alignment: .leading)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
            .strokeBorder(Color(leagueColor(season.league)).opacity(0.4)))
        .accessibilityElement(children: .combine)
    }
}
