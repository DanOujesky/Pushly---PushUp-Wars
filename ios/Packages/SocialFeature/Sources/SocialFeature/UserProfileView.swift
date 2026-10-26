import Core
import DesignSystem
import Observation
import SwiftUI

/// Player profile (doc 15 §1, P6-02): card, league, stats when visible, head-to-head, friend actions, report/block.
@MainActor
@Observable
public final class UserProfileModel {
    public enum Key: Hashable, Sendable {
        case id(String)
        case username(String)
    }

    public private(set) var profile: UserProfile?
    public private(set) var loaded = false
    public private(set) var notice: String?
    let key: Key
    private let service: SocialService

    public init(key: Key, service: SocialService) {
        self.key = key
        self.service = service
    }

    public func load() async {
        let (id, name): (String?, String?) = switch key {
        case let .id(id): (id, nil)
        case let .username(name): (nil, name)
        }
        do {
            profile = try JSONDecoder().decode(UserProfile?.self, from: try await service.profile(id, name))
        } catch {
            PLog.error("profile load failed: \(error)")
        }
        loaded = true
    }

    public func addFriend() async {
        guard let p = profile else { return }
        await run { _ = try await self.service.sendRequest(p.user.id) }
        PushPrompt.request(.friends)
    }

    public func accept() async {
        guard let p = profile else { return }
        await run { _ = try await self.service.respond(p.user.id, true) }
    }

    public func block() async {
        guard let p = profile else { return }
        await run { _ = try await self.service.block(p.user.id) }
        profile = nil
    }

    private func run(_ body: @escaping () async throws -> Void) async {
        do {
            try await body()
            notice = nil
        } catch {
            notice = String(localized: "That didn't work. Please try again.")
        }
        await load()
    }
}

/// Player profile (doc 15 §1, D-080): hero with avatar, league, trophies and clan; friend action; stat tiles, battle
/// record with form, last 7 days, progress, head to head; report / block. Opens from any player in the app.
public struct UserProfileView: View {
    @State private var model: UserProfileModel
    @State private var confirmBlock = false

    public init(model: UserProfileModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            if let p = model.profile {
                content(p)
            } else if model.loaded {
                VStack(spacing: SpacingTokens.s) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 44))
                        .foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
                    Text("This player isn't available.").foregroundStyle(Color(ColorTokens.textSecondary))
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .background { ProfileBackdrop(league: model.profile?.league.league ?? "bronze") }
        .navigationTitle(Text(verbatim: model.profile?.user.username ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .refreshable { await model.load() }
        .task { if model.profile == nil { await model.load() } }
        .confirmationDialog("Block this player?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await model.block() } }
        } message: {
            Text("You won't see each other anywhere in Pushly. They aren't told.")
        }
    }

    private func content(_ p: UserProfile) -> some View {
        VStack(spacing: SpacingTokens.m) {
            ProfileHero(profile: p)
            relationButton(p)
            if let notice = model.notice { InlineBanner(LocalizedStringKey(notice), kind: .warning) }
            if let s = p.stats {
                StatTiles(profile: p, stats: s)
                if let b = s.battles { BattleRecordCard(battles: b) }
                if let h = p.headToHead, h.wins + h.losses + h.draws > 0 { HeadToHeadCard(h: h, name: p.user.username) }
                if let days = s.last7, days.count == 7 { ActivityCard(days: days, week: s.repsWeek ?? days.reduce(0, +), stats: s) }
                ProgressCard(stats: s)
            } else {
                VStack(spacing: SpacingTokens.s) {
                    Image(systemName: "lock.fill").font(.title).foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
                    Text(p.relation == "friends" ? "This profile is private." : "Only friends can see these stats.")
                        .typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(SpacingTokens.l)
                .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
                if let h = p.headToHead, h.wins + h.losses + h.draws > 0 { HeadToHeadCard(h: h, name: p.user.username) }
            }
            if p.relation != "self" {
                HStack(spacing: SpacingTokens.m) {
                    ReportButton { reason in await Reporter.send(.user(p.user.id), reason: reason) }
                        .frame(minHeight: TouchTarget.minimum)
                    Spacer()
                    Button("Block", role: .destructive) { confirmBlock = true }
                        .frame(minHeight: TouchTarget.minimum)
                }
                .typography(TypographyTokens.caption)
                .padding(.horizontal, SpacingTokens.s)
            }
        }
        .padding(.horizontal, SpacingTokens.m)
        .padding(.bottom, SpacingTokens.xl)
    }

    @ViewBuilder
    private func relationButton(_ p: UserProfile) -> some View {
        switch p.relation {
        case "none": PrimaryButton("Add friend") { Task { await model.addFriend() } }
        case "incoming": PrimaryButton("Accept friend request") { Task { await model.accept() } }
        case "outgoing":
            Label("Friend request sent", systemImage: "paperplane.fill")
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                .background(Color(ColorTokens.bgSurface), in: Capsule())
        case "friends":
            Label("Friends", systemImage: "checkmark.circle.fill")
                .typography(TypographyTokens.titleS)
                .foregroundStyle(Color(ColorTokens.stateSuccessText))
                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                .background(Color(ColorTokens.stateSuccess).opacity(0.12), in: Capsule())
        default: EmptyView()
        }
    }
}

// MARK: - Pieces

func profileLeagueColor(_ league: String) -> TokenColor {
    switch league {
    case "bronze": ColorTokens.leagueBronze
    case "silver": ColorTokens.leagueSilver
    case "gold": ColorTokens.leagueGold
    case "platinum": ColorTokens.leaguePlatinum
    case "diamond": ColorTokens.leagueDiamond
    default: ColorTokens.leagueChampion
    }
}

enum ProfileText {
    static func league(_ l: UserProfile.League) -> String {
        let name = l.league.prefix(1).uppercased() + l.league.dropFirst()
        return l.tier.map { "\(name) \($0)" } ?? name
    }

    static func role(_ r: String) -> String {
        switch r {
        case "leader": String(localized: "Leader")
        case "co_leader": String(localized: "Co-leader")
        case "elder": String(localized: "Elder")
        default: String(localized: "Member")
        }
    }

    /// "Oct 2026" from "2026-10".
    static func since(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return ym }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[m - 1]) \(y)"
    }

    /// Weekday letters for the last 7 days, today last.
    static func lastWeekLetters(today: Date = Date(), calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).reversed().map { back in
            let d = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return symbols[(calendar.component(.weekday, from: d) - 1) % symbols.count]
        }
    }
}

struct ProfileBackdrop: View {
    let league: String

    var body: some View {
        ZStack {
            Color(ColorTokens.bgBase)
            RadialGradient(colors: [Color(profileLeagueColor(league)).opacity(0.28), .clear],
                           center: UnitPoint(x: 0.5, y: 0.12), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

/// Avatar with frame + level, name, PRO, league + trophies, clan chip (opens the clan).
struct ProfileHero: View {
    let profile: UserProfile

    var body: some View {
        let u = profile.user
        let tint = Color(profileLeagueColor(profile.league.league))
        VStack(spacing: SpacingTokens.s) {
            AvatarView(username: u.username, presetID: u.avatarPreset, size: 104, frame: u.frame)
                .overlay(alignment: .bottomTrailing) {
                    Text(verbatim: "\(profile.stats?.level ?? u.level)")
                        .typography(TypographyTokens.labelDisplay)
                        .foregroundStyle(Color(ColorTokens.bgBase))
                        .frame(minWidth: 30, minHeight: 30)
                        .background(LinearGradient(GradientTokens.hero), in: Circle())
                        .overlay(Circle().strokeBorder(Color(ColorTokens.bgBase), lineWidth: 3))
                        .accessibilityLabel(Text("Level \(profile.stats?.level ?? u.level)"))
                }
                .shadow(color: tint.opacity(0.45), radius: 24)
            HStack(spacing: SpacingTokens.xs) {
                Text(verbatim: u.username).typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if u.pro == true { ProBadge() }
            }
            HStack(spacing: SpacingTokens.s) {
                Label {
                    Text(verbatim: ProfileText.league(profile.league))
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .typography(TypographyTokens.titleS)
                .foregroundStyle(tint)
                Text(verbatim: "🏆 \(u.trophies)")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.leagueGold))
                if let country = u.country, let flag = Self.flag(country) { Text(verbatim: flag) }
            }
            .accessibilityElement(children: .combine)
            if let clan = profile.clan {
                ProfileLink(.clan(id: clan.id)) {
                    HStack(spacing: SpacingTokens.s) {
                        ClanEmblemView(style: clan.badge, tag: clan.tag, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: clan.name).typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                                .lineLimit(1)
                            Text(verbatim: "\(ProfileText.role(clan.role)) · 🛡️ \(clan.rating)")
                                .typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                    .padding(.horizontal, SpacingTokens.m)
                    .padding(.vertical, SpacingTokens.xs)
                    .frame(minHeight: TouchTarget.minimum)
                    .background(Color(ColorTokens.bgSurface).opacity(0.9), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(ColorTokens.strokeSubtle)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SpacingTokens.m)
    }

    static func flag(_ code: String) -> String? {
        guard code.count == 2 else { return nil }
        var out = ""
        for scalar in code.uppercased().unicodeScalars {
            guard let s = UnicodeScalar(127_397 + scalar.value) else { return nil }
            out.unicodeScalars.append(s)
        }
        return out
    }
}

/// Trophies (best), world rank, push-ups all time, best set.
struct StatTiles: View {
    let profile: UserProfile
    let stats: UserProfile.Stats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: SpacingTokens.s), GridItem(.flexible())], spacing: SpacingTokens.s) {
            tile("🏆", "\(profile.user.trophies)", String(localized: "Trophies"), String(localized: "Best \(stats.bestTrophies)"),
                 ColorTokens.leagueGold)
            tile("🌍", stats.rank.map { "#\($0)" } ?? "–", String(localized: "World rank"), String(localized: "by trophies"),
                 ColorTokens.brandCyan)
            tile("💪", "\(stats.repsTotal)", String(localized: "Push-ups"), String(localized: "all time"), ColorTokens.brandFlameText)
            tile("⭐", "\(stats.bestSet)", String(localized: "Best set"), String(localized: "in one go"), ColorTokens.brandVoltText)
        }
    }

    private func tile(_ glyph: String, _ value: String, _ title: String, _ sub: String, _ tint: TokenColor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: glyph).font(.title3).accessibilityHidden(true)
            Text(verbatim: value).typography(TypographyTokens.stat).foregroundStyle(Color(tint)).lineLimit(1).minimumScaleFactor(0.5)
            Text(verbatim: title).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textPrimary))
            Text(verbatim: sub).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
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
}

private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    content()
        .padding(SpacingTokens.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
}

/// Win-rate ring, W–L–D, last 10 results, streaks.
struct BattleRecordCard: View {
    let battles: UserProfile.Stats.Battles

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: SpacingTokens.m) {
                Text("Battles").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                HStack(spacing: SpacingTokens.l) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 9)
                        Circle().trim(from: 0, to: battles.winRate)
                            .stroke(LinearGradient(GradientTokens.success), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(verbatim: battles.played == 0 ? "–" : "\(Int((battles.winRate * 100).rounded()))%")
                                .typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textPrimary))
                            Text("win rate").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                    }
                    .frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: SpacingTokens.s) {
                        HStack(spacing: SpacingTokens.m) {
                            tally(battles.wins, "W", ColorTokens.stateSuccessText)
                            tally(battles.losses, "L", ColorTokens.stateDanger)
                            tally(battles.draws, "D", ColorTokens.textSecondary)
                        }
                        if !battles.form.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(Array(battles.form.reversed().enumerated()), id: \.offset) { _, o in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(o == "W" ? ColorTokens.stateSuccessText : o == "L" ? ColorTokens.stateDanger : ColorTokens.textSecondary))
                                        .frame(width: 14, height: 14)
                                        .overlay(Text(verbatim: o).font(.system(size: 8, weight: .heavy)).foregroundStyle(.black.opacity(0.6)))
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Last results: \(battles.form.joined(separator: " "))"))
                        }
                    }
                }
                HStack(spacing: SpacingTokens.s) {
                    if battles.winStreak > 1 { Pill("🔥 \(battles.winStreak) win streak", color: ColorTokens.brandFlameText) }
                    if battles.bestWinStreak > 0 { Pill("Best streak \(battles.bestWinStreak)", color: ColorTokens.textSecondary) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tally(_ n: Int, _ letter: String, _ color: TokenColor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(n)").typography(TypographyTokens.stat).foregroundStyle(Color(color))
            Text(verbatim: letter).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
        }
    }
}

/// You vs them, as a split bar.
struct HeadToHeadCard: View {
    let h: UserProfile.HeadToHead
    let name: String

    var body: some View {
        let total = max(h.wins + h.losses, 1)
        card {
            VStack(alignment: .leading, spacing: SpacingTokens.s) {
                Text("Head to head").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                HStack {
                    Text("You").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textSecondary))
                    Spacer()
                    Text(verbatim: "\(h.wins) – \(h.losses)").typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textPrimary))
                    Spacer()
                    Text(verbatim: name).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textSecondary)).lineLimit(1)
                }
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Capsule().fill(Color(ColorTokens.stateSuccessText))
                            .frame(width: max(6, geo.size.width * CGFloat(h.wins) / CGFloat(total)))
                        Capsule().fill(Color(ColorTokens.stateDanger))
                    }
                }
                .frame(height: 8)
                if h.draws > 0 {
                    Text("\(h.draws) draws").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Head to head: you \(h.wins), \(name) \(h.losses), \(h.draws) draws"))
    }
}

/// Last 7 days as bars, this week's total, wake streak.
struct ActivityCard: View {
    let days: [Int]
    let week: Int
    let stats: UserProfile.Stats

    var body: some View {
        let top = max(days.max() ?? 0, 1)
        let letters = ProfileText.lastWeekLetters()
        card {
            VStack(alignment: .leading, spacing: SpacingTokens.m) {
                HStack {
                    Text("Last 7 days").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                    Spacer()
                    Text("\(week) push-ups").typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.brandFlameText))
                }
                HStack(alignment: .bottom, spacing: SpacingTokens.s) {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 4) {
                            Text(verbatim: days[i] > 0 ? "\(days[i])" : "")
                                .font(.caption2.weight(.semibold)).foregroundStyle(Color(ColorTokens.textSecondary))
                                .lineLimit(1).minimumScaleFactor(0.5)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(days[i] > 0 ? AnyShapeStyle(LinearGradient(GradientTokens.hero)) : AnyShapeStyle(Color.white.opacity(0.08)))
                                .frame(height: max(6, 64 * CGFloat(days[i]) / CGFloat(top)))
                            Text(verbatim: letters[i]).typography(TypographyTokens.caption)
                                .foregroundStyle(Color(i == 6 ? ColorTokens.textPrimary : ColorTokens.textTertiary))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 100, alignment: .bottom)
                HStack(spacing: SpacingTokens.s) {
                    Pill("🔥 \(stats.wakeStreak ?? 0) day wake streak", color: ColorTokens.brandFlameText)
                    Pill("Best \(stats.bestStreak)", color: ColorTokens.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last 7 days: \(week) push-ups. Wake streak \(stats.wakeStreak ?? 0) days."))
    }
}

/// Level + XP, achievements, member since.
struct ProgressCard: View {
    let stats: UserProfile.Stats

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: SpacingTokens.s) {
                Text("Progress").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                row("Level", value: stats.level.map { "\($0)" + (stats.xp.map { " · \($0) XP" } ?? "") } ?? "–")
                VStack(alignment: .leading, spacing: 4) {
                    row("Achievements", value: stats.achievementsTotal.map { "\(stats.achievements) / \($0)" } ?? "\(stats.achievements)")
                    if let total = stats.achievementsTotal, total > 0 {
                        GradientProgressBar(value: Double(stats.achievements) / Double(total), height: 6)
                    }
                }
                row("Member since", value: ProfileText.since(stats.memberSince))
            }
        }
    }

    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title).typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.textSecondary))
            Spacer()
            Text(verbatim: value).typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}
