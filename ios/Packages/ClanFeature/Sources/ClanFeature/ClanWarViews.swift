import DesignSystem
import SwiftUI

// Clan Wars v2 (D-078): lobby → live → Sunday results, groups of 2–4 clans.

extension ClanWar: Identifiable {}

/// Which results the player has already seen (the result screen shows once per war, on this device).
enum WarResultSeen {
    private static let key = "clanWar.seenResults"

    static func contains(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id)
    }

    static func mark(_ id: String) {
        var seen = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !seen.contains(id) else { return }
        seen.append(id)
        UserDefaults.standard.set(Array(seen.suffix(30)), forKey: key)
    }
}

/// "2 d 4 h" / "3 h 12 min" until an ISO instant (nil when passed or unparsable).
enum WarClock {
    static func until(_ iso: String, now: Date = Date()) -> String? {
        guard let end = ISO8601DateFormatter().date(from: iso) else { return nil }
        let s = Int(end.timeIntervalSince(now))
        guard s > 0 else { return nil }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return String(localized: "\(d) d \(h) h") }
        if h > 0 { return String(localized: "\(h) h \(m) min") }
        return String(localized: "\(max(m, 1)) min")
    }
}

func rankMedal(_ rank: Int?) -> String {
    switch rank {
    case 1: "🥇"
    case 2: "🥈"
    case 3: "🥉"
    default: rank.map { "#\($0)" } ?? "–"
    }
}

/// The war on the clan lobby: who we fight, the clock, and (live) the standings.
struct WarCard: View {
    let war: ClanWar

    private var accent: Color { Color(war.isLive ? ColorTokens.stateDanger : ColorTokens.brandCyan) }

    var body: some View {
        VStack(spacing: SpacingTokens.sm) {
            header
            if war.isLobby { lobby } else { live }
            footer
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface).opacity(0.9), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(accent.opacity(0.55), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: SpacingTokens.xs) {
            Text(war.isLobby ? "NEXT CLAN WAR" : "CLAN WAR")
                .typography(TypographyTokens.overline)
                .foregroundStyle(Color(ColorTokens.textSecondary))
            Text(war.isLobby ? "LOBBY" : "LIVE")
                .typography(TypographyTokens.overline)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(accent, in: Capsule())
            Spacer()
            if let left = WarClock.until(war.isLobby ? war.startsAt : war.endsAt) {
                Label(war.isLobby ? "Starts in \(left)" : "Ends in \(left)", systemImage: "clock")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.brandFlameText))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    @ViewBuilder private var lobby: some View {
        if war.rivals.isEmpty {
            VStack(spacing: SpacingTokens.s) {
                if let mine = war.mine { ClanEmblemView(style: mine.clan.badge, tag: mine.clan.tag, size: 84) }
                Text("Looking for opponents…").typography(TypographyTokens.titleM).foregroundStyle(Color(ColorTokens.textPrimary))
                Text(war.movedWeeks > 0
                     ? "Nobody was free last week. Any clan that joins Pushly this week lands in this lobby."
                     : "Clans that join this week land in this lobby — up to 4 per war.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: SpacingTokens.xs) {
                ForEach(Array(war.clans.enumerated()), id: \.element.id) { i, s in
                    if i > 0 {
                        Text(verbatim: "VS").typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.textTertiary)).padding(.top, 20)
                    }
                    VStack(spacing: 4) {
                        ClanEmblemView(style: s.clan.badge, tag: s.clan.tag, size: war.clans.count > 3 ? 46 : 58)
                        Text(verbatim: s.clan.name)
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(s.isMine ? ColorTokens.brandFlameText : ColorTokens.textPrimary))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(verbatim: "🏆 \(s.clan.rating)").typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder private var live: some View {
        if war.clans.count == 2, let me = war.mine, let them = war.rivals.first {
            HStack(spacing: SpacingTokens.s) {
                duelSide(me)
                Text(verbatim: "VS").typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
                duelSide(them)
            }
            TugBar(us: me.score, them: them.score, ours: Color(badgeColor(me.clan)), theirs: Color(badgeColor(them.clan)))
                .frame(height: 14)
        } else {
            WarStandings(war: war, compact: true)
        }
    }

    private func duelSide(_ s: ClanWar.Standing) -> some View {
        VStack(spacing: SpacingTokens.xs) {
            ClanEmblemView(style: s.clan.badge, tag: s.clan.tag, size: 60)
            Text(verbatim: s.clan.name).typography(TypographyTokens.labelDisplay)
                .foregroundStyle(Color(s.isMine ? ColorTokens.brandFlameText : ColorTokens.textSecondary))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: "\(s.score)").typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(statusLine)
                .typography(TypographyTokens.titleS)
                .foregroundStyle(Color(statusColor))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            if let stakes = war.mine?.stakes, !war.rivals.isEmpty {
                Text(verbatim: "+\(stakes.win) / \(stakes.last) 🏆")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.leagueGold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(ColorTokens.leagueGold).opacity(0.14), in: Capsule())
                    .accessibilityLabel(Text("Win \(stakes.win) clan trophies, last place \(stakes.last)"))
            }
            Image(systemName: "chevron.right").foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
        }
    }

    private var statusLine: LocalizedStringKey {
        if war.isLobby {
            return war.rivals.isEmpty ? "Waiting in the lobby" : "\(war.clans.count) clans · starts Monday"
        }
        let rank = war.myRank ?? 1
        if war.gap > 0 { return "1st — ahead by \(war.gap)" }
        if war.gap == 0 { return "Tied for the lead" }
        return rank == 1 ? "Tied for the lead" : "#\(rank) — \(-war.gap) behind the leader"
    }

    private var statusColor: TokenColor {
        if war.isLobby { return ColorTokens.textPrimary }
        return war.gap > 0 ? ColorTokens.stateSuccessText : war.gap < 0 ? ColorTokens.stateDanger : ColorTokens.textPrimary
    }
}

/// Standings rows: medal, emblem, name, score bar (live) and clan trophies (finished).
struct WarStandings: View {
    let war: ClanWar
    var compact = false

    var body: some View {
        let top = max(war.clans.map(\.score).max() ?? 0, 1)
        VStack(spacing: compact ? SpacingTokens.xs : SpacingTokens.s) {
            ForEach(war.clans) { s in
                HStack(spacing: SpacingTokens.sm) {
                    Text(verbatim: rankMedal(s.rank)).font(compact ? .title3 : .title2).frame(width: 34)
                    ClanEmblemView(style: s.clan.badge, tag: s.clan.tag, size: compact ? 30 : 38)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(verbatim: s.clan.name)
                                .typography(TypographyTokens.titleS)
                                .foregroundStyle(Color(s.isMine ? ColorTokens.brandFlameText : ColorTokens.textPrimary))
                                .lineLimit(1)
                            Spacer(minLength: SpacingTokens.xs)
                            Text(verbatim: "\(s.score)").typography(TypographyTokens.titleS).monospacedDigit()
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.07))
                                Capsule().fill(Color(badgeColor(s.clan)))
                                    .frame(width: max(6, geo.size.width * CGFloat(s.score) / CGFloat(top)))
                            }
                        }
                        .frame(height: 6)
                        if !compact {
                            HStack(spacing: SpacingTokens.s) {
                                if let d = s.ratingDelta {
                                    Text(verbatim: d >= 0 ? "+\(d) 🏆" : "\(d) 🏆").typography(TypographyTokens.caption)
                                        .foregroundStyle(Color(d >= 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger))
                                } else if let st = s.stakes {
                                    Text("1st +\(st.win) · last \(st.last) 🏆").typography(TypographyTokens.caption)
                                        .foregroundStyle(Color(ColorTokens.textTertiary))
                                }
                                if let mvp = s.mvp {
                                    Text("MVP \(mvp.username)").typography(TypographyTokens.caption)
                                        .foregroundStyle(Color(ColorTokens.textSecondary))
                                }
                            }
                        }
                    }
                }
                .padding(compact ? 0 : SpacingTokens.s)
                .background(s.isMine && !compact ? Color(ColorTokens.brandFlame).opacity(0.10) : Color.clear,
                            in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Sunday results (D-078): shown first when the player opens the tab after a war, then the next lobby.
struct WarResultView: View {
    let war: ClanWar
    let onContinue: () -> Void

    private var won: Bool { war.result?.rank == 1 && (war.result?.of ?? 0) > 1 }
    private var delta: Int { war.result?.ratingDelta ?? 0 }

    var body: some View {
        ZStack {
            ClanBackdrop(color: won ? ColorTokens.leagueGold : (war.mine.map { badgeColor($0.clan) } ?? ColorTokens.brandCyan))
            ScrollView {
                VStack(spacing: SpacingTokens.l) {
                    Text("CLAN WAR RESULTS").typography(TypographyTokens.overline).foregroundStyle(Color(ColorTokens.textSecondary))
                        .padding(.top, SpacingTokens.xl)
                    if let mine = war.mine {
                        ClanEmblemView(style: mine.clan.badge, tag: mine.clan.tag, size: 120)
                            .shadow(color: Color(won ? ColorTokens.leagueGold : ColorTokens.brandFlame).opacity(0.6), radius: 24)
                    }
                    VStack(spacing: SpacingTokens.xs) {
                        Text(won ? "🏆 VICTORY!" : "#\(war.result?.rank ?? 0) of \(war.result?.of ?? 0)")
                            .typography(TypographyTokens.displayL)
                            .foregroundStyle(Color(won ? ColorTokens.leagueGold : ColorTokens.textPrimary))
                        Text(verbatim: delta >= 0 ? "+\(delta) clan trophies" : "\(delta) clan trophies")
                            .typography(TypographyTokens.titleM)
                            .foregroundStyle(Color(delta >= 0 ? ColorTokens.stateSuccessText : ColorTokens.stateDanger))
                    }
                    WarStandings(war: war)
                        .padding(SpacingTokens.m)
                        .background(Color(ColorTokens.bgSurface).opacity(0.92), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
                    if !war.top.isEmpty {
                        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                            SectionLabel("Our fighters")
                            ForEach(Array(war.top.enumerated()), id: \.offset) { i, t in
                                HStack(spacing: SpacingTokens.sm) {
                                    Text(verbatim: i == 0 ? "👑" : "\(i + 1).").frame(width: 28)
                                    AvatarView(username: t.user.username, presetID: t.user.avatarPreset, size: 30, frame: t.user.frame)
                                    Text(verbatim: t.user.username).typography(TypographyTokens.bodyS)
                                        .foregroundStyle(Color(ColorTokens.textPrimary))
                                    Spacer()
                                    Text(verbatim: "\(t.reps)").typography(TypographyTokens.titleS)
                                        .foregroundStyle(Color(ColorTokens.textPrimary))
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(SpacingTokens.m)
                        .background(Color(ColorTokens.bgSurface).opacity(0.92), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
                    }
                    Text("Your next Clan War is already waiting in the lobby — it starts on Monday.")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .multilineTextAlignment(.center)
                    PrimaryButton("See the next war", action: onContinue)
                }
                .padding(.horizontal, SpacingTokens.gutter)
                .padding(.bottom, SpacingTokens.xl)
            }
        }
    }
}

struct WarDetailsSheet: View {
    let model: ClanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    if let war = model.home?.war {
                        WarCard(war: war)
                        if war.isLive, let rally = war.rally {
                            RallyButton(available: rally.available, behind: war.gap < 0) { Task { await model.rally() } }
                                .frame(maxWidth: .infinity)
                        }
                        if !war.rivals.isEmpty {
                            card {
                                VStack(alignment: .leading, spacing: SpacingTokens.s) {
                                    Text(war.isLobby ? "In this war" : "Standings").typography(TypographyTokens.labelDisplay)
                                        .foregroundStyle(Color(ColorTokens.textSecondary))
                                    WarStandings(war: war)
                                }
                            }
                        }
                        if war.isLive { SideViewNotice(.compact) }
                        if !war.top.isEmpty {
                            card {
                                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                                    Text("Our fighters").typography(TypographyTokens.labelDisplay)
                                        .foregroundStyle(Color(ColorTokens.textSecondary))
                                    ForEach(Array(war.top.enumerated()), id: \.offset) { i, t in
                                        HStack(spacing: SpacingTokens.xs) {
                                            Text(verbatim: i == 0 ? "👑" : "\(i + 1).").typography(TypographyTokens.caption)
                                            Text(verbatim: t.user.username).typography(TypographyTokens.bodyS).lineLimit(1)
                                            Spacer(minLength: 0)
                                            Text(verbatim: "\(t.reps)").typography(TypographyTokens.bodyS)
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                        }
                        if !war.feed.isEmpty {
                            card { WarFeed(feed: war.feed) }
                        }
                        card { rules }
                    }
                }
                .padding(SpacingTokens.l)
            }
            .arenaBackground(glow: ColorTokens.brandFlame, alignment: .top, offset: CGSize(width: 0, height: -260))
            .refreshable { await model.load() }
            .navigationTitle(Text("Clan War"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("How Clan Wars work").typography(TypographyTokens.labelDisplay).foregroundStyle(Color(ColorTokens.textSecondary))
            ForEach([
                String(localized: "2–4 clans of similar strength fight each week."),
                String(localized: "The war runs from Monday 00:00 to Sunday 20:00 (UTC)."),
                String(localized: "Every member's verified push-ups score: full points up to 200 a day, half up to 400."),
                String(localized: "Places decide clan trophies — the more clans you beat, the more you win."),
                String(localized: "On Sunday you see the results and go straight into the lobby for the next war."),
            ], id: \.self) { line in
                Text(verbatim: "• " + line).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(SpacingTokens.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
    }
}

/// Live war feed: who just scored for which clan.
struct WarFeed: View {
    let feed: [ClanWar.FeedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("Live").typography(TypographyTokens.labelDisplay).foregroundStyle(Color(ColorTokens.stateDanger))
            ForEach(Array(feed.prefix(8).enumerated()), id: \.offset) { _, f in
                HStack {
                    Text(verbatim: f.mine ? "🔥" : "⚔️").accessibilityHidden(true)
                    Text(verbatim: f.username).typography(TypographyTokens.bodyS)
                    Text(verbatim: f.clanName).typography(TypographyTokens.caption)
                        .foregroundStyle(Color(f.mine ? ColorTokens.brandFlameText : ColorTokens.brandVoltText))
                        .lineLimit(1)
                    Spacer()
                    Text(verbatim: "+\(f.points)").typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(f.mine ? ColorTokens.stateSuccessText : ColorTokens.stateDanger))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - History

struct WarHistorySheet: View {
    let model: ClanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.warHistory.isEmpty {
                    Text("No finished wars yet. Results arrive every Sunday at 20:00 UTC.")
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                        .listRowBackground(Color(ColorTokens.bgSurface))
                } else {
                    Section {
                        ForEach(model.warHistory) { war in WarHistoryRow(war: war) }
                    } header: {
                        HStack {
                            SectionLabel("Last wars")
                            Spacer()
                            if let streak = WarStreak.current(model.warHistory), streak.letter == "W", streak.count > 1 {
                                Pill("\(streak.count) wins in a row", color: ColorTokens.stateSuccessText)
                            }
                        }
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                }
            }
            .scrollContentBackground(.hidden)
            .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -260))
            .navigationTitle(Text("War history"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct WarHistoryRow: View {
    let war: ClanWarResult

    var body: some View {
        HStack(spacing: SpacingTokens.sm) {
            VStack(spacing: 0) {
                Text(verbatim: rankMedal(war.rank)).font(.title2)
                Text("of \(war.of)").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: -6) {
                    ForEach(war.clans.filter { !$0.isMine }) { c in
                        ClanEmblemView(style: c.badge, tag: c.tag, size: 26)
                    }
                }
                Text(verbatim: war.clans.filter { !$0.isMine }.map(\.name).joined(separator: ", "))
                    .typography(TypographyTokens.bodyS).lineLimit(1)
                Text(verbatim: war.weekStart).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "\(war.score)").typography(TypographyTokens.titleS)
                Text(verbatim: war.ratingDelta >= 0 ? "+\(war.ratingDelta) 🏆" : "\(war.ratingDelta) 🏆")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(war.ratingDelta >= 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger))
            }
        }
        .frame(minHeight: TouchTarget.minimum)
        .accessibilityElement(children: .combine)
    }
}
