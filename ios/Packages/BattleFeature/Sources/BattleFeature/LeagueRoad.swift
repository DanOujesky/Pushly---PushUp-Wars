import Core
import DesignSystem
import SwiftUI

/// Tap the league emblem → the trophy road (D-076, Clash Royale style): every league from Bronze up to Legend on one
/// road, the stretch you've covered lit in gold, you on it, and how far the next stop is. Static — nothing moves.
struct LeagueRoadSheet: View {
    let arena: ArenaStatus?
    let player: BattlePlayer?
    @Environment(\.dismiss) private var dismiss

    private var trophies: Int { arena?.trophies ?? 0 }
    private var current: LeagueLadder.Rung { LeagueLadder.rung(for: trophies) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: SpacingTokens.l) {
                        header
                        if let targets = arena?.targets, !targets.isEmpty { above(targets) }
                        VStack(spacing: 0) {
                            ForEach(Array(LeagueLadder.rungs.reversed().enumerated()), id: \.element.id) { i, rung in
                                RoadStop(rung: rung, trophies: trophies, isCurrent: rung == current, isTop: i == 0,
                                         player: player)
                                    .id(rung.id)
                            }
                        }
                        rules
                    }
                    .padding(.horizontal, SpacingTokens.gutter)
                    .padding(.vertical, SpacingTokens.l)
                }
                .background { RoadBackdrop(league: current.league) }
                .navigationTitle(Text("Trophy road"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { proxy.scrollTo(current.id, anchor: .center) }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(spacing: SpacingTokens.sm) {
            LeagueEmblem(league: current.league, tier: current.tier)
                .frame(width: 120, height: 130)
            Text(verbatim: leagueTitle(current.league, current.tier))
                .typography(TypographyTokens.titleL)
                .foregroundStyle(Color(leagueColor(current.league)))
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: "trophy.fill").foregroundStyle(Color(ColorTokens.leagueGold))
                Text(verbatim: "\(trophies)").typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
            }
            if let to = current.to {
                let next = LeagueLadder.rung(for: to + 1)
                GradientProgressBar(value: Double(trophies - current.from) / Double(max(to + 1 - current.from, 1)), height: 10)
                    .frame(maxWidth: 260)
                Text("\(to + 1 - trophies) 🏆 to \(leagueTitle(next.league, next.tier))")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            HStack(spacing: SpacingTokens.s) {
                if let arena { Pill("Best \(arena.bestTrophies) 🏆") }
                if let rank = arena?.rank { Pill("#\(rank) in the world", color: ColorTokens.brandFlameText) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func above(_ targets: [ArenaStatus.Target]) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            SectionLabel("Just above you")
            ForEach(targets) { t in
                HStack(spacing: SpacingTokens.sm) {
                    AvatarView(username: t.username, presetID: t.avatarPreset, size: 32)
                    Text(verbatim: t.username).typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.textPrimary))
                    Spacer()
                    Text(verbatim: "\(t.trophies) 🏆").typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.textPrimary))
                    Text(verbatim: "+\(t.gap)").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.brandFlameText))
                }
                .frame(minHeight: TouchTarget.minimum)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface).opacity(0.9), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            SectionLabel("How it works")
            Label("Safe floors: once you reach 600, 1,200 or 2,000 trophies in a season, you can't drop below them until it ends.",
                  systemImage: "shield.lefthalf.filled")
            Label("Season end (1st of every month): above 2,000 trophies, half of everything over 2,000 is kept. Your best league earns a badge.",
                  systemImage: "calendar")
            Label("Only BATTLE moves trophies — real opponents and Arena Bots. Friends and practice bots never do.", systemImage: "bolt.fill")
        }
        .typography(TypographyTokens.caption)
        .foregroundStyle(Color(ColorTokens.textSecondary))
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface).opacity(0.9), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
    }
}

/// One stop on the road: the road segment, a node, and the league card (big for the first tier of a league).
struct RoadStop: View {
    let rung: LeagueLadder.Rung
    let trophies: Int
    let isCurrent: Bool
    let isTop: Bool
    let player: BattlePlayer?

    private var reached: Bool { rung.from <= trophies }
    /// The first tier of a league (III, Champion, Legend) gets the big card with the emblem.
    private var isGate: Bool { rung.tier == nil || rung.tier == "III" }

    var body: some View {
        let color = Color(leagueColor(rung.league))
        HStack(alignment: .center, spacing: SpacingTokens.m) {
            ZStack {
                // the road: lit up to where you are
                VStack(spacing: 0) {
                    Rectangle().fill(isTop ? Color.clear : roadColor(above: true)).frame(width: 6)
                    Rectangle().fill(roadColor(above: false)).frame(width: 6)
                }
                node(color)
            }
            .frame(width: 64)
            card(color)
        }
        .frame(minHeight: isGate ? 128 : 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(a11y))
    }

    private func roadColor(above: Bool) -> Color {
        // the stretch below a reached stop is covered; above the current one it's still ahead
        let covered = above ? (reached && !isCurrent) : reached
        return covered ? Color(ColorTokens.leagueGold) : Color.white.opacity(0.12)
    }

    @ViewBuilder private func node(_ color: Color) -> some View {
        if isCurrent {
            ZStack {
                Circle().fill(color.opacity(0.25)).frame(width: 60, height: 60)
                if let player {
                    AvatarView(username: player.username, presetID: player.avatarPreset, size: 46, frame: ProState.shared.myFrame)
                } else {
                    Image(systemName: "person.fill").font(.title2).foregroundStyle(.white)
                }
            }
        } else if isGate {
            Circle()
                .fill(reached ? color : Color(ColorTokens.bgElevated))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.white.opacity(reached ? 0.6 : 0.2), lineWidth: 2))
                .overlay {
                    Image(systemName: reached ? "checkmark" : "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(reached ? Color(ColorTokens.bgBase) : Color(ColorTokens.textTertiary))
                }
        } else {
            Circle()
                .fill(reached ? color : Color(ColorTokens.strokeStrong))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
    }

    @ViewBuilder private func card(_ color: Color) -> some View {
        if isGate {
            HStack(spacing: SpacingTokens.m) {
                LeagueEmblem(league: rung.league, tier: rung.tier)
                    .frame(width: 70, height: 76)
                    .saturation(reached ? 1 : 0.15)
                    .opacity(reached ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: leagueTitle(rung.league, rung.tier))
                        .typography(TypographyTokens.titleM)
                        .foregroundStyle(reached ? color : Color(ColorTokens.textSecondary))
                    Text(verbatim: "\(rung.from) 🏆")
                        .typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    status
                }
                Spacer(minLength: 0)
            }
            .padding(SpacingTokens.sm)
            .background(
                LinearGradient(colors: [color.opacity(reached ? 0.28 : 0.08), Color(ColorTokens.bgSurface).opacity(0.92)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
                .strokeBorder(isCurrent ? color : color.opacity(reached ? 0.5 : 0.15), lineWidth: isCurrent ? 2 : 1))
        } else {
            HStack {
                Text(verbatim: leagueTitle(rung.league, rung.tier))
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(isCurrent ? color : reached ? Color(ColorTokens.textPrimary) : Color(ColorTokens.textTertiary))
                Text(verbatim: "· \(rung.from) 🏆")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                Spacer(minLength: 0)
                status
            }
            .padding(.horizontal, SpacingTokens.sm)
            .frame(minHeight: TouchTarget.minimum)
            .background(isCurrent ? color.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        }
    }

    @ViewBuilder private var status: some View {
        if isCurrent {
            Pill("You are here", color: ColorTokens.brandFlameText)
        } else if reached {
            if LeagueLadder.floors.contains(rung.from) {
                Text("Safe floor").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.stateSuccessText))
            }
        } else {
            Text("+\(rung.from - trophies) to go")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
        }
    }

    private var a11y: String {
        let title = leagueTitle(rung.league, rung.tier)
        if isCurrent { return String(localized: "\(title), from \(rung.from) trophies. You are here.") }
        if reached { return String(localized: "\(title), from \(rung.from) trophies. Reached.") }
        return String(localized: "\(title), from \(rung.from) trophies. \(rung.from - trophies) to go.")
    }
}

/// Dark arena with the current league's glow.
struct RoadBackdrop: View {
    let league: String

    var body: some View {
        ZStack {
            Color(ColorTokens.bgBase)
            RadialGradient(colors: [Color(leagueColor(league)).opacity(0.28), .clear],
                           center: UnitPoint(x: 0.5, y: 0.1), startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
