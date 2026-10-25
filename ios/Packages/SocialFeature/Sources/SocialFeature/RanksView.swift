import DesignSystem
import SwiftUI

/// Ranks tab (PS-60…PS-63, doc 08 §4): board, scope and period pickers, top 100, own row pinned.
public struct RanksView: View {
    @State private var model: RanksModel

    public init(model: RanksModel) {
        _model = State(initialValue: model)
    }

    private func boardTitle(_ b: Board) -> LocalizedStringKey {
        switch b {
        case .wake: "Wake"
        case .streak: "Streak"
        case .reps: "Push-ups"
        }
    }

    private func periodTitle(_ p: String) -> LocalizedStringKey {
        switch p {
        case "day": "Today"
        case "week": "Week"
        case "month": "Month"
        case "all": "All time"
        default: "Now"
        }
    }

    private func scopeTitle(_ s: String) -> LocalizedStringKey {
        switch s {
        case "global": "Global"
        case "country": "Country"
        default: "Friends"
        }
    }

    private func scoreUnit(_ b: Board) -> LocalizedStringKey {
        switch b {
        case .wake: "points"
        case .streak: "days"
        case .reps: "push-ups"
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.m) {
                    ScreenTitle("Ranks", token: TypographyTokens.displayM)
                    Picker("Board", selection: Binding(get: { model.board }, set: { b in Task { await model.select(board: b) } })) {
                        ForEach(Board.allCases) { Text(boardTitle($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: SpacingTokens.s) {
                        ForEach(["global", "country", "friends"], id: \.self) { s in
                            chip(scopeTitle(s), on: model.scope == s) {
                                Task { await model.select(scope: s) }
                            }
                        }
                    }
                    if model.board.periods.count > 1 {
                        HStack(spacing: SpacingTokens.s) {
                            ForEach(model.board.periods, id: \.self) { p in
                                chip(periodTitle(p), on: model.period == p) { Task { await model.select(period: p) } }
                            }
                        }
                    }
                    Text("Weeks and months reset in UTC.")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                    content
                    // bottom of the list (doc 13 §1)
                    AdBannerSlot("ranks_banner")
                }
                .padding(.horizontal, SpacingTokens.l)
                .padding(.bottom, SpacingTokens.xl)
            }
            .safeAreaInset(edge: .bottom) {
                if let me = model.pinnedMe {
                    RankRow(row: me, unit: scoreUnit(model.board))
                        .padding(.horizontal, SpacingTokens.l)
                        .padding(.vertical, SpacingTokens.s)
                        .background(.ultraThinMaterial)
                }
            }
            .refreshable { await model.load(force: true) }
            .arenaBackground(glow: ColorTokens.leagueGold, alignment: .top, offset: CGSize(width: 0, height: -260))
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let board = model.current {
            if board.needsCountry == true {
                InlineBanner("Set your country in your profile to see the country board.", kind: .info)
            } else if board.rows.isEmpty {
                Text("Nobody here yet — beat a wake challenge to be the first.")
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            if board.me?.shadow == true {
                InlineBanner("Your recent sessions are being checked, so only you can see your rank for now.", kind: .warning)
            }
            LazyVStack(spacing: SpacingTokens.s) {
                ForEach(board.rows) { RankRow(row: $0, unit: scoreUnit(model.board)) }
                if !board.around.isEmpty {
                    Text(verbatim: "···").foregroundStyle(Color(ColorTokens.textTertiary))
                    ForEach(board.around) { RankRow(row: $0, unit: scoreUnit(model.board)) }
                }
            }
        } else if model.failed {
            InlineBanner("Ranks couldn't load. Pull down to try again.", kind: .warning)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func chip(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .typography(TypographyTokens.bodyS)
                .padding(.horizontal, SpacingTokens.m)
                .frame(minHeight: TouchTarget.minimum)
                .foregroundStyle(Color(on ? ColorTokens.textPrimary : ColorTokens.textTertiary))
                .background(Color(on ? ColorTokens.bgElevated : ColorTokens.bgSurface), in: Capsule())
                .overlay(Capsule().stroke(Color(on ? ColorTokens.brandFlame : ColorTokens.strokeSubtle), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct RankRow: View {
    let row: Leaderboard.Row
    let unit: LocalizedStringKey

    private var medal: Color? {
        switch row.rank {
        case 1: Color(ColorTokens.leagueGold)
        case 2: Color(ColorTokens.leagueSilver)
        case 3: Color(ColorTokens.leagueBronze)
        default: nil
        }
    }

    var body: some View {
        let name = row.user.anonymous == true ? String(localized: "Anonymous athlete") : (row.user.username ?? "")
        HStack(spacing: SpacingTokens.m) {
            Text(verbatim: "\(row.rank)")
                .typography(TypographyTokens.titleS)
                .foregroundStyle(medal ?? Color(ColorTokens.textSecondary))
                .frame(minWidth: 36, alignment: .leading)
            AvatarView(username: name, presetID: row.user.avatarPreset, size: 36)
            Text(verbatim: name)
                .typography(TypographyTokens.bodyS)
                .fontWeight(row.isMe ? .bold : .regular)
                .lineLimit(1)
            if row.user.pro == true { ProBadge() }
            Spacer(minLength: 0)
            Text(verbatim: "\(row.score)")
                .typography(TypographyTokens.titleS)
                .foregroundStyle(Color(ColorTokens.textPrimary))
        }
        .padding(.horizontal, SpacingTokens.m)
        .frame(minHeight: 52)
        .background(Color(row.isMe ? ColorTokens.bgElevated : ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m)
            .stroke(Color(row.isMe ? ColorTokens.brandFlame : ColorTokens.strokeSubtle), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rank \(row.rank), \(name), \(row.score)") + Text(" ") + Text(unit))
    }
}
