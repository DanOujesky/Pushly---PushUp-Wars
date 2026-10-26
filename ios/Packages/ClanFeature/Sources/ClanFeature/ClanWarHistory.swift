import DesignSystem
import SwiftUI

// Clan War history + "who pushed" (D-079): a record card like Battle history, every finished war as a result card,
// and per war the fighters of every clan with points per day — leaders see who pulled their weight.

/// Pushes inside the clan sheets: a clan's page or a war's fighters.
enum ClanRoute: Hashable {
    case clan(String)
    case fighters(warId: String, clanId: String?)
}

extension View {
    func clanRoutes(_ model: ClanModel) -> some View {
        navigationDestination(for: ClanRoute.self) { route in
            switch route {
            case let .clan(id): ClanProfileView(model: model, clanId: id)
            case let .fighters(warId, clanId): WarFightersView(model: model, warId: warId, clanId: clanId)
            }
        }
    }
}

enum WarDates {
    /// "19 Oct – 25 Oct" for the Monday of a war week.
    static func week(_ monday: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "yyyy-MM-dd"
        guard let start = f.date(from: monday) else { return monday }
        let end = start.addingTimeInterval(6 * 86400)
        f.dateFormat = "d MMM"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    /// M T W T F S S
    static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
}

func placeColor(_ rank: Int, of: Int) -> TokenColor {
    if rank == 1, of > 1 { return ColorTokens.leagueGold }
    if rank == of { return ColorTokens.stateDanger }
    return ColorTokens.textSecondary
}

// MARK: - History sheet

struct WarHistorySheet: View {
    let model: ClanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SpacingTokens.m) {
                    WarRecordCard(record: WarRecord(model.warHistory))
                    if model.warHistory.isEmpty {
                        VStack(spacing: SpacingTokens.s) {
                            Text(verbatim: "🏰").font(.system(size: 44)).accessibilityHidden(true)
                            Text("No finished wars yet").typography(TypographyTokens.titleM)
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                            Text("Results arrive every Sunday at 20:00 UTC — every war shows up here with who pushed how much.")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textSecondary))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingTokens.xl)
                    } else {
                        SectionLabel("Last wars").padding(.top, SpacingTokens.s)
                        ForEach(model.warHistory) { war in
                            NavigationLink(value: ClanRoute.fighters(warId: war.id, clanId: nil)) {
                                WarResultCard(war: war)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, SpacingTokens.m)
                .padding(.bottom, SpacingTokens.xl)
            }
            .background(Color(ColorTokens.bgBase).ignoresSafeArea())
            .refreshable { await model.loadWarExtras() }
            .navigationTitle(Text("War history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .clanRoutes(model)
        }
    }
}

/// Win rate ring, wins / wars, the last 10 places, trophies, best streak.
struct WarRecordCard: View {
    let record: WarRecord

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            HStack(spacing: SpacingTokens.l) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: record.winRate)
                        .stroke(LinearGradient(GradientTokens.success), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(verbatim: record.played == 0 ? "–" : "\(Int((record.winRate * 100).rounded()))%")
                            .typography(TypographyTokens.titleL)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                        Text("wars won").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: SpacingTokens.s) {
                    HStack(spacing: SpacingTokens.m) {
                        tally(record.wins, String(localized: "won"), ColorTokens.leagueGold)
                        tally(record.played, String(localized: "wars"), ColorTokens.textPrimary)
                    }
                    if !record.form.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last \(record.form.count) places").typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                            HStack(spacing: 4) {
                                ForEach(Array(record.form.reversed().enumerated()), id: \.offset) { _, rank in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(rank == 1 ? ColorTokens.leagueGold : ColorTokens.bgElevated))
                                        .frame(width: 16, height: 16)
                                        .overlay {
                                            Text(verbatim: "\(rank)")
                                                .font(.system(size: 9, weight: .heavy))
                                                .foregroundStyle(rank == 1 ? .black.opacity(0.7) : Color(ColorTokens.textSecondary))
                                        }
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: SpacingTokens.s) {
                if record.trophyNet != 0 {
                    Pill(LocalizedStringKey(record.trophyNet > 0 ? "+\(record.trophyNet) 🏆 clan trophies" : "\(record.trophyNet) 🏆 clan trophies"),
                         color: record.trophyNet > 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger)
                }
                if record.bestStreak > 1 { Pill("🔥 Best streak \(record.bestStreak)", color: ColorTokens.brandFlameText) }
            }
        }
        .padding(SpacingTokens.ml)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(ColorTokens.brandVolt).opacity(0.18), Color(ColorTokens.bgSurface)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .accessibilityElement(children: .combine)
    }

    private func tally(_ n: Int, _ label: String, _ color: TokenColor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: "\(n)").typography(TypographyTokens.stat).foregroundStyle(Color(color))
            Text(verbatim: label).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
        }
    }
}

/// One finished war: place banner, every clan with its score, trophies, MVP and fighters.
struct WarResultCard: View {
    let war: ClanWarResult

    private var won: Bool { war.letter == "W" }
    private var tint: Color { Color(placeColor(war.rank, of: war.of)) }

    private var title: LocalizedStringKey {
        if won { return "VICTORY" }
        if war.rank == war.of { return "LAST PLACE" }
        return war.rank == 2 ? "2ND PLACE" : "3RD PLACE"
    }

    var body: some View {
        let top = max(war.clans.map(\.score).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack {
                Text(title).typography(TypographyTokens.titleM).foregroundStyle(tint)
                Text("of \(war.of)").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                Spacer()
                Text(verbatim: war.ratingDelta >= 0 ? "+\(war.ratingDelta) 🏆" : "\(war.ratingDelta) 🏆")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(war.ratingDelta >= 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger))
            }
            Text(verbatim: WarDates.week(war.weekStart)).typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
            ForEach(war.clans) { c in
                HStack(spacing: SpacingTokens.sm) {
                    Text(verbatim: rankMedal(c.rank)).frame(width: 28)
                    ClanEmblemView(style: c.badge, tag: c.tag, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(verbatim: c.name).typography(TypographyTokens.bodyS)
                                .foregroundStyle(Color(c.isMine ? ColorTokens.brandFlameText : ColorTokens.textPrimary))
                                .lineLimit(1)
                            Spacer(minLength: SpacingTokens.xs)
                            Text(verbatim: "\(c.score)").typography(TypographyTokens.bodyS).monospacedDigit()
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                        }
                        GeometryReader { geo in
                            Capsule().fill(Color(c.isMine ? ColorTokens.brandFlame : ColorTokens.textTertiary).opacity(c.isMine ? 1 : 0.5))
                                .frame(width: max(5, geo.size.width * CGFloat(c.score) / CGFloat(top)))
                        }
                        .frame(height: 5)
                    }
                }
            }
            HStack(spacing: SpacingTokens.s) {
                if let mvp = war.mvp {
                    AvatarView(username: mvp.username, presetID: mvp.avatarPreset, size: 26, frame: mvp.frame)
                    Text("MVP \(mvp.username)").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textSecondary))
                        .lineLimit(1)
                }
                if let n = war.contributors {
                    Text("· \(n) fighters").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                }
                Spacer()
                Text("Who pushed").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.brandFlameText))
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color(ColorTokens.textTertiary))
            }
            .padding(.top, 2)
        }
        .padding(SpacingTokens.m)
        .background(
            LinearGradient(colors: [tint.opacity(won ? 0.16 : 0.08), Color(ColorTokens.bgSurface)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(tint.opacity(won ? 0.5 : 0.2)))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows who did how many push-ups"))
    }
}

// MARK: - Who pushed

/// Every clan's fighters in one war, points per day; members who did nothing are flagged (D-079).
struct WarFightersView: View {
    let model: ClanModel
    let warId: String
    let clanId: String?
    @State private var detail: ClanWarDetail?
    @State private var selected: String?
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let detail {
                content(detail)
            } else if failed {
                InlineBanner("This war couldn't load. Pull down to try again.", kind: .warning).padding(SpacingTokens.m)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
        .navigationTitle(Text("Who pushed"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if detail == nil { await load() } }
    }

    private func load() async {
        let d = await model.warDetail(warId)
        failed = d == nil
        if let d {
            detail = d
            if selected == nil { selected = clanId ?? d.mySide?.clanId }
        }
    }

    @ViewBuilder private func content(_ d: ClanWarDetail) -> some View {
        let side = selected.flatMap(d.side) ?? d.mySide
        let standing = d.war.clans.first { $0.clan.id == side?.clanId }
        LazyVStack(alignment: .leading, spacing: SpacingTokens.m) {
            Text(verbatim: WarDates.week(d.war.weekStart)).typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
            ScrollView(.horizontal) {
                HStack(spacing: SpacingTokens.s) {
                    ForEach(d.war.clans) { s in clanChip(s, on: s.clan.id == side?.clanId) }
                }
            }
            .scrollIndicators(.hidden)
            if let side, let standing {
                summary(side, standing)
                header
                ForEach(Array(side.fighters.enumerated()), id: \.element.id) { i, f in
                    FighterRow(place: i + 1, fighter: f, scale: max(side.bestDay, 1))
                }
                if side.fighters.isEmpty {
                    Text("Nobody in this clan scored.").typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                }
                Text("Points count verified side-view push-ups: full points up to 200 a day, half up to 400.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .padding(SpacingTokens.m)
    }

    private func clanChip(_ s: ClanWar.Standing, on: Bool) -> some View {
        Button {
            selected = s.clan.id
        } label: {
            HStack(spacing: SpacingTokens.xs) {
                Text(verbatim: rankMedal(s.rank))
                ClanEmblemView(style: s.clan.badge, tag: s.clan.tag, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: s.clan.name).typography(TypographyTokens.caption)
                        .foregroundStyle(Color(s.isMine ? ColorTokens.brandFlameText : ColorTokens.textPrimary)).lineLimit(1)
                    Text(verbatim: "\(s.score)").typography(TypographyTokens.labelDisplay).foregroundStyle(Color(ColorTokens.textSecondary))
                }
            }
            .padding(.horizontal, SpacingTokens.sm)
            .frame(minHeight: TouchTarget.minimum)
            .background(Color(on ? ColorTokens.bgElevated : ColorTokens.bgSurface), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color(badgeColor(s.clan)) : Color(ColorTokens.strokeSubtle), lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func summary(_ side: ClanWarDetail.Side, _ s: ClanWar.Standing) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack(spacing: SpacingTokens.m) {
                ClanEmblemView(style: s.clan.badge, tag: s.clan.tag, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: s.clan.name).typography(TypographyTokens.titleM).foregroundStyle(Color(ColorTokens.textPrimary))
                    Text("\(side.active) of \(side.fighters.count) fought · \(s.score) points")
                        .typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textSecondary))
                }
                Spacer(minLength: 0)
                NavigationLink(value: ClanRoute.clan(s.clan.id)) {
                    Image(systemName: "info.circle").font(.title3)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                }
                .accessibilityLabel(Text("About \(s.clan.name)"))
            }
            if !side.idle.isEmpty {
                Label("\(side.idle.count) members didn't push at all", systemImage: "exclamationmark.triangle.fill")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.stateWarning))
            }
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: SpacingTokens.sm) {
            Spacer().frame(width: 24 + 36 + SpacingTokens.sm)
            Spacer()
            HStack(spacing: 3) {
                ForEach(Array(WarDates.dayLetters.enumerated()), id: \.offset) { _, l in
                    Text(verbatim: l).font(.system(size: 9, weight: .bold)).foregroundStyle(Color(ColorTokens.textTertiary))
                        .frame(width: 9)
                }
            }
            Text("Points").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, SpacingTokens.sm)
        .accessibilityHidden(true)
    }
}

/// Place, avatar, name, the 7 war days as mini bars, points.
struct FighterRow: View {
    let place: Int
    let fighter: ClanWarDetail.Fighter
    let scale: Int

    var body: some View {
        HStack(spacing: SpacingTokens.sm) {
            Text(verbatim: place <= 3 && fighter.points > 0 ? ["🥇", "🥈", "🥉"][place - 1] : "\(place)")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
                .frame(width: 24)
            AvatarView(username: fighter.user.username, presetID: fighter.user.avatarPreset, size: 36, frame: fighter.user.frame)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpacingTokens.xs) {
                    Text(verbatim: fighter.user.username).typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary)).lineLimit(1)
                    if !fighter.inClan { Pill("Left", color: ColorTokens.textTertiary) }
                }
                Text(fighter.points == 0 ? "Didn't fight" : "\(fighter.raw) push-ups")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(fighter.points == 0 ? ColorTokens.stateDanger : ColorTokens.textTertiary))
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(fighter.days.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(v > 0 ? AnyShapeStyle(LinearGradient(GradientTokens.hero)) : AnyShapeStyle(Color.white.opacity(0.08)))
                        .frame(width: 9, height: max(3, 26 * CGFloat(v) / CGFloat(scale)))
                }
            }
            .frame(height: 26, alignment: .bottom)
            Text(verbatim: "\(fighter.points)")
                .typography(TypographyTokens.titleM)
                .monospacedDigit()
                .foregroundStyle(Color(fighter.points == 0 ? ColorTokens.stateDanger : ColorTokens.textPrimary))
                .frame(width: 52, alignment: .trailing)
        }
        .padding(SpacingTokens.sm)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(fighter.points == 0
                                 ? "\(fighter.user.username), didn't fight"
                                 : "\(fighter.user.username), \(fighter.points) points, \(fighter.raw) push-ups"))
    }
}
