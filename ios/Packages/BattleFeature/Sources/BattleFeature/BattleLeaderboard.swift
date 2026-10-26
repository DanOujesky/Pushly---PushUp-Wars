import Core
import DesignSystem
import SwiftUI

/// Leaderboard (D-075): only what Battle is about — trophies (global or friends) and clans by rating. Personal boards
/// (wake points, streaks, push-up totals) are gone from the app's tabs.
struct LeaderboardSheet: View {
    let model: BattleHubModel
    @State private var tab = Tab.players
    @State private var scope = "global"
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case players, clans
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Board", selection: $tab) {
                        Text("Players").tag(Tab.players)
                        Text("Clans").tag(Tab.clans)
                    }
                    .pickerStyle(.segmented)
                    if tab == .players {
                        Picker("Scope", selection: $scope) {
                            Text("World").tag("global")
                            Text("Friends").tag("friends")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .listRowBackground(Color.clear)
                if model.boardFailed {
                    Section { InlineBanner("Couldn't load the leaderboard. Pull to try again.", kind: .info) }
                        .listRowBackground(Color.clear)
                }
                if tab == .players { players } else { clans }
            }
            .scrollContentBackground(.hidden)
            .arenaBackground(glow: ColorTokens.leagueGold, alignment: .top, offset: CGSize(width: 0, height: -260))
            .navigationTitle(Text("Leaderboard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(tab.rawValue)-\(scope)") { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        if tab == .players { await model.loadTrophyBoard(scope: scope) } else { await model.loadClanBoard() }
    }

    @ViewBuilder private var players: some View {
        if let board = model.trophyBoard {
            if let me = board.me, !board.rows.contains(where: \.isMe) {
                Section {
                    PlayerRow(row: TrophyBoard.Row(rank: me.rank, score: me.score, isMe: true,
                                                   user: TrophyBoard.User(username: String(localized: "You"))))
                } header: { SectionLabel("You") }
                .listRowBackground(Color(ColorTokens.bgElevated))
            }
            Section {
                if board.rows.isEmpty {
                    Text("No one here yet — win a battle to get on the board.")
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                }
                ForEach(board.rows) { PlayerRow(row: $0) }
            } header: {
                SectionLabel(scope == "global" ? "Top 100 · this season" : "You and your friends")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        } else if !model.boardFailed {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var clans: some View {
        Section {
            if model.clanBoard.isEmpty, !model.boardFailed {
                Text("No clans yet.").foregroundStyle(Color(ColorTokens.textTertiary))
            }
            ForEach(model.clanBoard) { ClanRow(row: $0) }
        } header: {
            SectionLabel("Top clans by war rating")
        } footer: {
            Text("Clan Wars pair clans of similar size and rating every Monday. Winning raises the rating.")
                .typography(TypographyTokens.caption)
        }
        .listRowBackground(Color(ColorTokens.bgSurface))
    }
}

private func medal(_ rank: Int) -> Color {
    switch rank {
    case 1: Color(ColorTokens.leagueGold)
    case 2: Color(ColorTokens.leagueSilver)
    case 3: Color(ColorTokens.leagueBronze)
    default: Color(ColorTokens.textTertiary)
    }
}

struct PlayerRow: View {
    let row: TrophyBoard.Row

    var body: some View {
        let name = row.user.anonymous == true ? String(localized: "Anonymous") : (row.user.username ?? "?")
        HStack(spacing: SpacingTokens.sm) {
            Text(verbatim: "\(row.rank)")
                .typography(TypographyTokens.titleS)
                .foregroundStyle(medal(row.rank))
                .frame(minWidth: 34, alignment: .leading)
            AvatarView(username: name, presetID: row.user.avatarPreset, size: 36, frame: row.user.frame)
            HStack(spacing: SpacingTokens.xs) {
                Text(verbatim: name)
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(row.isMe ? ColorTokens.brandFlameText : ColorTokens.textPrimary))
                    .lineLimit(1)
                if row.user.pro == true { ProBadge() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Color(ColorTokens.leagueGold))
                Text(verbatim: "\(row.score)").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
            }
        }
        .frame(minHeight: TouchTarget.minimum)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rank \(row.rank), \(name), \(row.score) trophies"))
    }
}

struct ClanRow: View {
    let row: ClanBoardRow

    var body: some View {
        HStack(spacing: SpacingTokens.sm) {
            Text(verbatim: "\(row.rank)")
                .typography(TypographyTokens.titleS)
                .foregroundStyle(medal(row.rank))
                .frame(minWidth: 34, alignment: .leading)
            ClanEmblemView(style: row.clan.badge, tag: row.clan.tag, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.clan.name)
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(row.isMine ? ColorTokens.brandFlameText : ColorTokens.textPrimary))
                    .lineLimit(1)
                Text("\(row.clan.memberCount)/30 members")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled").font(.caption).foregroundStyle(Color(ColorTokens.brandCyan))
                Text(verbatim: "\(row.score)").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
            }
        }
        .frame(minHeight: TouchTarget.minimum)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rank \(row.rank), \(row.clan.name), rating \(row.score)"))
    }
}
