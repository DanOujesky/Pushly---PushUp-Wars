import DesignSystem
import SwiftUI

/// Any clan's page (D-079) — a rival from the war or your own: badge, description, rating, members, war record and
/// the current war, then every member with role, trophies and their points in this week's war.
struct ClanProfileView: View {
    let model: ClanModel
    let clanId: String
    @State private var home: ClanHome?
    @State private var results: [ClanWarResult] = []
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let home {
                content(home)
            } else if failed {
                InlineBanner("This clan couldn't load. Pull down to try again.", kind: .warning).padding(SpacingTokens.m)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background { ClanBackdrop(color: home.map { badgeColor($0.summary) } ?? ColorTokens.brandCyan) }
        .navigationTitle(Text(verbatim: home?.summary.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if home == nil { await load() } }
    }

    private func load() async {
        // one after the other — `async let` here crashed release builds (D-079 follow-up)
        let (fresh, wars) = await model.clanPage(clanId)
        failed = fresh == nil
        if let fresh { home = fresh }
        results = wars
    }

    private func content(_ home: ClanHome) -> some View {
        let s = home.summary
        let record = WarRecord(results)
        let members = home.members.sorted {
            (ClanRole(rawValue: $0.role)?.rank ?? 0, $0.user.trophies ?? 0) > (ClanRole(rawValue: $1.role)?.rank ?? 0, $1.user.trophies ?? 0)
        }
        return VStack(spacing: SpacingTokens.m) {
            VStack(spacing: SpacingTokens.s) {
                ClanEmblemView(style: s.badge, tag: s.tag, size: 112)
                    .shadow(color: Color(badgeColor(s)).opacity(0.5), radius: 20)
                Text(verbatim: s.name).typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
                    .multilineTextAlignment(.center)
                if s.myRole != nil { Pill("Your clan", color: ColorTokens.brandFlameText) }
                if !s.description.isEmpty {
                    Text(verbatim: s.description).typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, SpacingTokens.m)
            .accessibilityElement(children: .combine)

            HStack(spacing: SpacingTokens.s) {
                stat("🛡️", "\(s.rating)", String(localized: "Clan trophies"), ColorTokens.leagueGold)
                stat("👥", "\(s.memberCount)/\(s.maxMembers)", String(localized: "Members"), ColorTokens.brandCyan)
                stat("⚔️", record.played == 0 ? "–" : "\(record.wins)/\(record.played)", String(localized: "Wars won"), ColorTokens.stateSuccessText)
            }

            HStack(spacing: SpacingTokens.s) {
                Pill(LocalizedStringKey(policyText(s.joinPolicy)), color: ColorTokens.textSecondary)
                if s.minTrophies > 0 { Pill("Min \(s.minTrophies) 🏆", color: ColorTokens.textSecondary) }
                if let war = home.war { Pill(LocalizedStringKey(warText(war)), color: war.isLive ? ColorTokens.stateDanger : ColorTokens.textSecondary) }
            }

            if !record.form.isEmpty { WarRecordCard(record: record) }

            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                SectionLabel("Members \(s.memberCount)/\(s.maxMembers)")
                ForEach(members) { m in memberRow(m) }
            }
        }
        .padding(.horizontal, SpacingTokens.m)
        .padding(.bottom, SpacingTokens.xl)
    }

    private func stat(_ glyph: String, _ value: String, _ label: String, _ tint: TokenColor) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: glyph).accessibilityHidden(true)
            Text(verbatim: value).typography(TypographyTokens.titleM).foregroundStyle(Color(tint)).lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: label).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary)).lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpacingTokens.sm)
        .background(Color(ColorTokens.bgSurface).opacity(0.92), in: RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func memberRow(_ m: ClanHome.Member) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            AvatarView(username: m.user.username, presetID: m.user.avatarPreset, size: 40, frame: m.user.frame)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpacingTokens.xs) {
                    Text(verbatim: m.user.username).typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                        .lineLimit(1)
                    if m.user.pro == true { ProBadge() }
                }
                Text(verbatim: roleTitle(ClanRole(rawValue: m.role) ?? .member).capitalized
                     + (m.user.level.map { " · " + String(localized: "Level \($0)") } ?? ""))
                    .typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "🏆 \(m.user.trophies ?? 0)").typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.leagueGold))
                Text("\(m.warReps) this war").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .padding(SpacingTokens.sm)
        .frame(minHeight: TouchTarget.minimum)
        .background(Color(ColorTokens.bgSurface).opacity(0.92), in: RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func policyText(_ p: String) -> String {
        switch p {
        case "open": String(localized: "Anyone can join")
        case "request": String(localized: "Join by request")
        default: String(localized: "Invite only")
        }
    }

    private func warText(_ war: ClanWar) -> String {
        war.isLive ? String(localized: "In a Clan War") : String(localized: "In the war lobby")
    }
}
