import Core
import DesignSystem
import SwiftUI
import WakeFlowFeature

/// Who is playing — shown in the arena top bar and the matchmaking screen.
public struct BattlePlayer: Equatable, Sendable {
    public let username: String
    public let avatarPreset: String?

    public init(username: String, avatarPreset: String?) {
        self.username = username
        self.avatarPreset = avatarPreset
    }
}

/// Battle tab (doc 07, D-071): one screen, no scrolling, like a game lobby. The arena shows your league and trophies;
/// pick a mode and hit BATTLE (ranked quick match — the only way to win or lose trophies). Friends (always
/// friendly), Practice (bots) and History open as sheets. Battles open full screen.
public struct BattleHubView: View {
    @State private var model: BattleHubModel
    @AppStorage("battle.mode") private var modeRaw = BattleMode.maxReps.rawValue
    @State private var sheet: HubSheet?
    /// True while a sheet animates away — a battle cover waits for it (two presentations at once get dropped).
    @State private var sheetClosing = false
    private let sessions: SessionServices?
    private let player: BattlePlayer?

    enum HubSheet: String, Identifiable {
        case friends, practice, history, ladder, leaderboard
        var id: String { rawValue }
    }

    public init(model: BattleHubModel, sessions: SessionServices?, player: BattlePlayer? = nil) {
        _model = State(initialValue: model)
        self.sessions = sessions
        self.player = player
    }

    enum HubCover: Identifiable {
        case searching
        case battle(Battle)

        var id: String {
            switch self {
            case .searching: "searching"
            case let .battle(b): b.id
            }
        }
    }

    private var cover: Binding<HubCover?> {
        Binding(get: {
            guard sheet == nil, !sheetClosing else { return nil }
            if let active = model.active { return .battle(active) }
            return model.queuedMode != nil ? .searching : nil
        }, set: { value in
            if value == nil { model.active = nil }
        })
    }

    private func closeSheet() {
        guard sheet != nil else { return }
        sheetClosing = true
        sheet = nil
    }

    private static let quickModes = BattleMode.allCases.filter(\.quickMatch)

    private var mode: BattleMode {
        let m = BattleMode(rawValue: modeRaw) ?? .maxReps
        return m.quickMatch ? m : .maxReps
    }

    public var body: some View {
        ViewThatFits(in: .vertical) {
            lobby
            ScrollView { lobby }.scrollIndicators(.hidden)
        }
        .background { ArenaBackdrop(league: model.arena?.league ?? "bronze") }
        .overlay(alignment: .top) { toast }
        .task { await model.load() }
        .onChange(of: model.active?.id) { _, id in if id != nil { closeSheet() } }
        .refreshable { await model.load() }
        .sheet(item: $sheet, onDismiss: { sheetClosing = false }) { which in
            switch which {
            case .friends: FriendBattleSheet(model: model, player: player) { closeSheet() }
            case .practice: PracticeSheet(model: model, mode: mode) { closeSheet() }
            case .history: HistorySheet(model: model, player: player)
            case .ladder: LeagueRoadSheet(arena: model.arena, player: player)
            case .leaderboard: LeaderboardSheet(model: model)
            }
        }
        // One cover for search → battle, so the hand-over from matchmaking to the battle is never dropped.
        .fullScreenCover(item: cover, onDismiss: { Task { await model.load() } }) { which in
            switch which {
            case .searching:
                MatchmakingView(model: model, player: player)
            case let .battle(battle):
                LiveBattleView(model: LiveBattleModel(battle: battle, service: model.service, sessions: sessions),
                               onClose: { model.active = nil },
                               onRematch: { finished in
                                   model.active = nil
                                   Task { await model.rematch(finished) }
                               })
            }
        }
    }

    // MARK: lobby

    private var lobby: some View {
        VStack(spacing: SpacingTokens.m) {
            topBar
            Spacer(minLength: SpacingTokens.s)
            Button { sheet = .ladder } label: { ArenaHero(arena: model.arena) }
                .buttonStyle(PressDimStyle())
                .accessibilityHint(Text("Shows every league and where you are"))
            Spacer(minLength: SpacingTokens.s)
            if let invite = model.openInvites.first {
                InviteBanner(invite: invite, more: model.openInvites.count - 1,
                             onFight: { Task { await model.accept(invite) } },
                             onDecline: { Task { await model.decline(invite) } })
            }
            modePicker
            battleButton
            HStack(spacing: SpacingTokens.sm) {
                HubTile(symbol: "person.2.fill", title: "Friends", subtitle: "No trophies",
                        badge: model.openInvites.count, tint: ColorTokens.brandCyan) { sheet = .friends }
                HubTile(symbol: "cpu", title: "Practice", subtitle: "Practice bots", badge: 0,
                        tint: ColorTokens.brandLime) { sheet = .practice }
                HubTile(symbol: "clock.arrow.circlepath", title: "History", subtitle: historySubtitle, badge: 0,
                        tint: ColorTokens.brandVolt) { sheet = .history }
            }
            // same height for all three tiles, whatever their text
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpacingTokens.gutter)
        .padding(.top, SpacingTokens.s)
        .padding(.bottom, SpacingTokens.m)
    }

    private var historySubtitle: LocalizedStringKey {
        guard let r = model.arena?.record else { return "Your battles" }
        return "\(r.wins) W · \(r.losses) L"
    }

    private var topBar: some View {
        HStack(spacing: SpacingTokens.sm) {
            if let player {
                AvatarView(username: player.username, presetID: player.avatarPreset, size: 40, frame: ProState.shared.myFrame)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: player.username)
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .lineLimit(1)
                    // trophies right under the name, always visible (D-076)
                    Button { sheet = .ladder } label: {
                        HStack(spacing: SpacingTokens.xs) {
                            Image(systemName: "trophy.fill").foregroundStyle(Color(ColorTokens.leagueGold))
                            Text(verbatim: "\(model.arena?.trophies ?? 0)")
                                .typography(TypographyTokens.titleS)
                                .foregroundStyle(Color(ColorTokens.leagueGold))
                            if let r = model.arena?.record, r.winStreak > 1 {
                                Text("· 🔥 \(r.winStreak)")
                                    .typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.brandFlameText))
                            }
                        }
                    }
                    .buttonStyle(PressDimStyle())
                    .accessibilityLabel(Text("\(model.arena?.trophies ?? 0) trophies"))
                }
                .accessibilityElement(children: .contain)
            } else {
                Text("Battle").typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
            }
            Spacer()
            Button { sheet = .leaderboard } label: {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "trophy.fill").foregroundStyle(Color(ColorTokens.leagueGold))
                    Text("Leaderboard")
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                }
                .padding(.horizontal, SpacingTokens.sm)
                .frame(minHeight: TouchTarget.minimum)
                .background(Color.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(ColorTokens.leagueGold).opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(PressDimStyle())
        }
        .frame(minHeight: TouchTarget.minimum)
    }

    private var modePicker: some View {
        let modes = Self.quickModes
        let index = modes.firstIndex(of: mode) ?? 0
        return HStack(spacing: SpacingTokens.s) {
            chevron("chevron.left", label: "Previous mode") { modeRaw = modes[(index + modes.count - 1) % modes.count].rawValue }
            VStack(spacing: 2) {
                Text(verbatim: modeTitle(mode.rawValue, mode.variant))
                    .typography(TypographyTokens.titleM)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text(verbatim: modeBlurb(mode))
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PageDots(count: modes.count, index: index)
                    .padding(.top, SpacingTokens.xs)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 24).onEnded { g in
                if g.translation.width < -24 { modeRaw = modes[(index + 1) % modes.count].rawValue }
                if g.translation.width > 24 { modeRaw = modes[(index + modes.count - 1) % modes.count].rawValue }
            })
            .accessibilityElement(children: .combine)
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: modeRaw = modes[(index + 1) % modes.count].rawValue
                case .decrement: modeRaw = modes[(index + modes.count - 1) % modes.count].rawValue
                @unknown default: break
                }
            }
            chevron("chevron.right", label: "Next mode") { modeRaw = modes[(index + 1) % modes.count].rawValue }
        }
    }

    private func chevron(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .accessibilityLabel(Text(label))
    }

    private var battleButton: some View {
        BattleButton(subtitle: "Ranked · win trophies") { Task { await model.quickMatch(mode) } }
    }

    @ViewBuilder private var toast: some View {
        if let notice = model.notice {
            Text(verbatim: notice)
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .padding(SpacingTokens.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).strokeBorder(Color(ColorTokens.strokeStrong)))
                .padding(.horizontal, SpacingTokens.gutter)
                .padding(.top, SpacingTokens.xs)
                .onTapGesture { model.clearNotice() }
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(4))
                    model.clearNotice()
                }
        }
    }
}

func modeBlurb(_ mode: BattleMode) -> String {
    switch mode {
    case .maxReps: String(localized: "Most push-ups in 60 seconds wins.")
    case .speed: String(localized: "First to 20 push-ups wins.")
    case .bestOf3: String(localized: "Three rounds, one set each — win two.")
    case .turns: String(localized: "One rep each, back and forth. Miss your 5 s window and you lose.")
    case .endurance: String(localized: "One long set — pause 3 s or drop the plank and you're out.")
    }
}

func leagueColor(_ league: String) -> TokenColor {
    switch league {
    case "bronze": ColorTokens.leagueBronze
    case "silver": ColorTokens.leagueSilver
    case "gold": ColorTokens.leagueGold
    case "platinum": ColorTokens.leaguePlatinum
    case "diamond": ColorTokens.leagueDiamond
    default: ColorTokens.leagueChampion
    }
}

// MARK: - Arena

/// Dark arena with a glow in the league's colour and faint floor lines.
struct ArenaBackdrop: View {
    let league: String

    var body: some View {
        ZStack {
            Color(ColorTokens.bgBase)
            RadialGradient(colors: [Color(leagueColor(league)).opacity(0.32), .clear],
                           center: UnitPoint(x: 0.5, y: 0.34), startRadius: 10, endRadius: 360)
            Canvas { ctx, size in
                // perspective floor lines under the emblem
                let horizon = size.height * 0.62
                for i in 0..<9 {
                    let t = CGFloat(i) / 8
                    var p = Path()
                    p.move(to: CGPoint(x: size.width / 2, y: horizon))
                    p.addLine(to: CGPoint(x: size.width * (t * 1.6 - 0.3), y: size.height))
                    ctx.stroke(p, with: .color(.white.opacity(0.035)), lineWidth: 1)
                }
                for j in 1..<6 {
                    let y = horizon + (size.height - horizon) * pow(CGFloat(j) / 5, 1.6)
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.white.opacity(0.03)), lineWidth: 1)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// League emblem, trophies, progress to the next step, world rank and season end.
struct ArenaHero: View {
    let arena: ArenaStatus?

    var body: some View {
        VStack(spacing: SpacingTokens.sm) {
            LeagueEmblem(league: arena?.league ?? "bronze", tier: arena?.tier)
                .frame(width: 148, height: 160)
            Text(verbatim: leagueTitle(arena?.league ?? "bronze", arena?.tier))
                .typography(TypographyTokens.labelDisplay)
                .foregroundStyle(Color(leagueColor(arena?.league ?? "bronze")))
            if let arena {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "trophy.fill").foregroundStyle(Color(ColorTokens.leagueGold))
                    Text(verbatim: "\(arena.trophies)")
                        .typography(TypographyTokens.titleL)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(arena.trophies) trophies"))
            }
            if let arena {
                VStack(spacing: SpacingTokens.xs) {
                    GradientProgressBar(value: arena.progress, height: 10)
                        .frame(maxWidth: 260)
                    if let next = arena.next {
                        Text("\(next.at - arena.trophies) 🏆 to \(leagueTitle(next.league, next.tier))")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    } else {
                        Text("Top league reached").typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    }
                }
                HStack(spacing: SpacingTokens.s) {
                    if let rank = arena.rank { Pill("#\(rank) in the world", color: ColorTokens.brandFlameText) }
                    if let days = arena.seasonDaysLeft() { Pill("Season ends in \(days) d") }
                }
                Label("All leagues", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.brandFlameText))
            } else {
                Text("Win battles to earn trophies and climb leagues.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A shield in the league's colour with the tier and a soft halo behind it. Static (D-072: the lobby doesn't move).
struct LeagueEmblem: View {
    let league: String
    let tier: String?

    var body: some View {
        let color = Color(leagueColor(league))
        ZStack {
            AngularGradient(colors: [color.opacity(0), color.opacity(0.35), color.opacity(0), color.opacity(0.35), color.opacity(0)],
                            center: .center)
                .mask(Circle())
                .scaleEffect(1.25)
                .blur(radius: 6)
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .shadow(color: color.opacity(0.6), radius: 18)
            Image(systemName: "shield")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.35))
            VStack(spacing: 0) {
                Text(verbatim: leagueGlyph(league)).font(.system(size: 40))
                if let tier {
                    Text(verbatim: tier)
                        .typography(TypographyTokens.displayM)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
            }
            .offset(y: -6)
        }
        .accessibilityHidden(true)
    }
}

/// The big call to action: ranked quick match.
struct BattleButton: View {
    let subtitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("BATTLE")
                    .typography(TypographyTokens.displayL)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .typography(TypographyTokens.overline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(LinearGradient(GradientTokens.hero), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
            .shadow(color: Color(ColorTokens.brandFlame).opacity(0.45), radius: 18, y: 6)
        }
        .buttonStyle(PressDimStyle())
    }
}

/// Pressed = slightly dimmed, nothing moves.
struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Square-ish tile under the battle button.
struct HubTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let badge: Int
    let tint: TokenColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpacingTokens.xs) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(tint))
                    .frame(height: 30)
                Text(title)
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 96)
            .background(Color(ColorTokens.bgSurface).opacity(0.9), in: RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous)
                .strokeBorder(Color(tint).opacity(0.35), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text(verbatim: "\(badge)")
                        .typography(TypographyTokens.tab)
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Color(ColorTokens.stateDanger), in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(PressDimStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(badge > 0 ? Text("\(badge) challenges waiting") : Text(""))
    }
}

/// An incoming friend challenge, right above the battle button.
struct InviteBanner: View {
    let invite: BattleInvites.Incoming
    let more: Int
    let onFight: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: SpacingTokens.sm) {
            AvatarView(username: invite.from.username, presetID: invite.from.avatarPreset, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(invite.from.username) challenges you!")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .lineLimit(1)
                Text(verbatim: modeTitle(invite.mode, invite.variant) + (more > 0 ? " · +\(more)" : ""))
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            Spacer(minLength: 0)
            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            .accessibilityLabel(Text("Decline"))
            Button(action: onFight) {
                Text("Fight")
                    .typography(TypographyTokens.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SpacingTokens.m)
                    .frame(minHeight: TouchTarget.minimum)
                    .background(LinearGradient(GradientTokens.hero), in: Capsule())
            }
        }
        .padding(.horizontal, SpacingTokens.sm)
        .padding(.vertical, SpacingTokens.xs)
        .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).strokeBorder(Color(ColorTokens.brandCyan), lineWidth: 1.5))
    }
}

// MARK: - Matchmaking

/// Full-screen search: you in a ring, the mode, a timer; a ranked Arena Bot after 10 s (D-075). Only the timer changes.
struct MatchmakingView: View {
    let model: BattleHubModel
    let player: BattlePlayer?

    var body: some View {
        VStack(spacing: SpacingTokens.l) {
            Spacer()
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .strokeBorder(Color(ColorTokens.brandFlame).opacity(0.5 - Double(i) * 0.15), lineWidth: 2)
                        .frame(width: 120 + CGFloat(i) * 48, height: 120 + CGFloat(i) * 48)
                }
                if let player {
                    AvatarView(username: player.username, presetID: player.avatarPreset, size: 96, frame: ProState.shared.myFrame)
                } else {
                    Image(systemName: "bolt.fill").font(.system(size: 48)).foregroundStyle(Color(ColorTokens.brandFlameText))
                }
            }
            .frame(width: 220, height: 220)
            .accessibilityHidden(true)
            VStack(spacing: SpacingTokens.xs) {
                Text("Finding an opponent")
                    .typography(TypographyTokens.displayM)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                if let mode = model.queuedMode {
                    Text(verbatim: modeTitle(mode.rawValue, mode.variant))
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.brandFlameText))
                }
                Text(verbatim: String(format: "%d:%02d", model.waitedS / 60, model.waitedS % 60))
                    .typography(TypographyTokens.stat)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text("Matched with players near your trophies. If nobody is around after \(BattleHubModel.arenaBotAfterS) s, an Arena Bot at your level steps in. Ranked — trophies are on the line.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SideViewNotice(.compact)
            Spacer()
            GhostButton("Cancel") { Task { await model.cancelQueue() } }
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandFlame, alignment: .center)
        .onAppear { AppActivity.battlePhase = "matchmaking" }
        .onDisappear { if AppActivity.battlePhase == "matchmaking" { AppActivity.battlePhase = "none" } }
    }
}

// MARK: - Sheets

/// Friendly battles (D-071): pick a mode, challenge a friend. Never changes trophies.
struct FriendBattleSheet: View {
    let model: BattleHubModel
    let player: BattlePlayer?
    let onClose: () -> Void
    @State private var mode: BattleMode = .maxReps

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    InlineBanner("Friendly battles are just for fun — no trophies won or lost.", kind: .info)
                    if !model.openInvites.isEmpty {
                        SectionLabel("Challenges for you")
                        ForEach(model.openInvites) { inv in
                            InviteBanner(invite: inv, more: 0,
                                         onFight: { Task { await model.accept(inv) } },
                                         onDecline: { Task { await model.decline(inv) } })
                        }
                    }
                    if !model.friendRequests.isEmpty {
                        SectionLabel("Friend requests")
                        ForEach(model.friendRequests) { req in
                            HStack(spacing: SpacingTokens.sm) {
                                AvatarView(username: req.username, presetID: req.avatarPreset, size: 40)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: req.username).typography(TypographyTokens.titleS)
                                        .foregroundStyle(Color(ColorTokens.textPrimary))
                                    Text("wants to be friends").typography(TypographyTokens.caption)
                                        .foregroundStyle(Color(ColorTokens.textSecondary))
                                }
                                Spacer()
                                Button { Task { await model.respondFriend(req.id, accept: false) } } label: {
                                    Image(systemName: "xmark").font(.body.weight(.bold))
                                        .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                                        .background(Color(ColorTokens.bgSurface), in: Circle())
                                }
                                .foregroundStyle(Color(ColorTokens.textSecondary))
                                .accessibilityLabel(Text("Decline \(req.username)"))
                                Button { Task { await model.respondFriend(req.id, accept: true) } } label: {
                                    Text("Accept").typography(TypographyTokens.button).foregroundStyle(.white)
                                        .padding(.horizontal, SpacingTokens.m)
                                        .frame(minHeight: TouchTarget.minimum)
                                        .background(Color(ColorTokens.brandFlame), in: Capsule())
                                }
                            }
                        }
                    }
                    SectionLabel("Mode")
                    ModeChips(modes: BattleMode.allCases, selected: $mode)
                    Text(verbatim: modeBlurb(mode))
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                    SectionLabel("Challenge a friend")
                    if model.friends.isEmpty {
                        Text("No friends yet — add some below.")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                    ForEach(model.friends) { friend in
                        HStack(spacing: SpacingTokens.sm) {
                            AvatarView(username: friend.username, presetID: friend.avatarPreset, size: 40)
                            Text(verbatim: friend.username)
                                .typography(TypographyTokens.titleS)
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                            Spacer()
                            if model.invites.outgoing.contains(where: { $0.to?.id == friend.id && $0.status == "pending" }) {
                                Text("Waiting…")
                                    .typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.textTertiary))
                            }
                            Button {
                                Task { await model.challenge(friend, mode: mode) }
                            } label: {
                                Label("Challenge", systemImage: "bolt.fill")
                                    .typography(TypographyTokens.button)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, SpacingTokens.m)
                                    .frame(minHeight: TouchTarget.minimum)
                                    .background(Color(ColorTokens.brandFlame), in: Capsule())
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    AddFriendsSection(model: model, player: player)
                    if let notice = model.notice {
                        InlineBanner(LocalizedStringKey(notice), kind: .info)
                    }
                }
                .padding(SpacingTokens.l)
            }
            .background(Color(ColorTokens.bgBase).ignoresSafeArea())
            .navigationTitle(Text("Friendly battle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
            .task {
                // requests and newly accepted friends appear while the sheet is open (D-078)
                while !Task.isCancelled {
                    await model.loadFriends()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Practice (no trophies): labelled bots at five levels, or a ghost run of a real player.
struct PracticeSheet: View {
    let model: BattleHubModel
    let onClose: () -> Void
    @State private var mode: BattleMode
    @State private var level: BotLevel = .rookie

    init(model: BattleHubModel, mode: BattleMode, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _mode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    Group {
                        Text("Computer opponents, always marked with 🤖. XP only — no trophies, no leaderboard.")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                        SectionLabel("Level")
                        VStack(spacing: SpacingTokens.xs) {
                            ForEach(BotLevel.allCases) { l in
                                Button { level = l } label: {
                                    HStack {
                                        Text(verbatim: l.title)
                                            .typography(TypographyTokens.titleS)
                                            .foregroundStyle(Color(ColorTokens.textPrimary))
                                        Spacer()
                                        Text(verbatim: l.pace)
                                            .typography(TypographyTokens.caption)
                                            .foregroundStyle(Color(ColorTokens.textSecondary))
                                        Image(systemName: level == l ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Color(level == l ? ColorTokens.brandLime : ColorTokens.textTertiary))
                                    }
                                    .padding(.horizontal, SpacingTokens.m)
                                    .frame(minHeight: TouchTarget.minimum)
                                    .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.s))
                                }
                                .accessibilityAddTraits(level == l ? .isSelected : [])
                            }
                        }
                    }
                    SectionLabel("Mode")
                    ModeChips(modes: BattleMode.allCases.filter(\.quickMatch), selected: $mode)
                    Text(verbatim: modeBlurb(mode))
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                    PrimaryButton("Fight the bot") {
                        onClose()
                        Task { await model.practice(mode, level: level) }
                    }
                }
                .padding(SpacingTokens.l)
            }
            .background(Color(ColorTokens.bgBase).ignoresSafeArea())
            .navigationTitle(Text("Practice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onClose) } }
        }
        .presentationDetents([.large])
    }
}

/// Horizontal mode chips.
struct ModeChips: View {
    let modes: [BattleMode]
    @Binding var selected: BattleMode

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SpacingTokens.s) {
                ForEach(modes) { m in
                    Button { selected = m } label: {
                        Text(verbatim: modeTitle(m.rawValue, m.variant))
                            .typography(TypographyTokens.button)
                            .foregroundStyle(Color(selected == m ? ColorTokens.bgBase : ColorTokens.textPrimary))
                            .padding(.horizontal, SpacingTokens.m)
                            .frame(minHeight: TouchTarget.minimum)
                            .background(selected == m ? AnyShapeStyle(LinearGradient(GradientTokens.hero))
                                                      : AnyShapeStyle(Color(ColorTokens.bgSurface)), in: Capsule())
                    }
                    .accessibilityAddTraits(selected == m ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Label with the icon after the text ("All leagues ›").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

// MARK: - Adding friends (D-072)

/// Three ways to add a friend right where you challenge them: username search, share your link, show your QR code
/// (the other phone's camera opens your profile and they tap Add).
struct AddFriendsSection: View {
    let model: BattleHubModel
    let player: BattlePlayer?
    @State private var query = ""
    @State private var showQR = false
    @State private var scanning = false
    @State private var scannedName: String?

    private var link: URL? {
        player.flatMap { ShareLinks.profile($0.username) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionLabel("Add friends")
            HStack(spacing: SpacingTokens.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
                TextField(text: $query, prompt: Text("Find by username")) { Text("Find by username") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(.horizontal, SpacingTokens.m)
            .frame(minHeight: TouchTarget.minimum)
            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(300))
                await model.searchUsers(query)
            }
            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                if model.userHits.isEmpty {
                    Text("Nobody found.").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                }
                ForEach(model.userHits) { user in
                    HStack(spacing: SpacingTokens.sm) {
                        AvatarView(username: user.username, presetID: user.avatarPreset, size: 36)
                        Text(verbatim: user.username)
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                        Spacer()
                        switch user.relation {
                        case "friends": Pill("Friends", color: ColorTokens.stateSuccessText)
                        case "outgoing": Pill("Requested")
                        case "incoming":
                            Button { Task { await model.respondFriend(user.id, accept: true) } } label: {
                                Text("Accept")
                                    .typography(TypographyTokens.button)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, SpacingTokens.m)
                                    .frame(minHeight: TouchTarget.minimum)
                                    .background(Color(ColorTokens.brandFlame), in: Capsule())
                            }
                        default:
                            Button { Task { await model.addFriend(user) } } label: {
                                Label("Add", systemImage: "person.badge.plus")
                                    .typography(TypographyTokens.button)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, SpacingTokens.m)
                                    .frame(minHeight: TouchTarget.minimum)
                                    .background(Color(ColorTokens.brandFlame), in: Capsule())
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let link {
                HStack(spacing: SpacingTokens.sm) {
                    ShareLink(item: link, message: Text("Add me on Pushly and let's battle!")) {
                        Label("Share my link", systemImage: "square.and.arrow.up")
                            .typography(TypographyTokens.button)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                    }
                    Button { showQR = true } label: {
                        Label("My QR", systemImage: "qrcode")
                            .typography(TypographyTokens.button)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                    }
                    Button { scanning = true } label: {
                        Label("Scan", systemImage: "qrcode.viewfinder")
                            .typography(TypographyTokens.button)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                    }
                }
                Text("Next to each other? One of you shows the QR code, the other taps Scan — or uses the phone camera.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .sheet(isPresented: $showQR) {
            if let link, let player { QRCodeSheet(url: link, username: player.username) }
        }
        .sheet(isPresented: $scanning, onDismiss: {
            // the profile opens through the app's deep link handling (pushly://u/<name>)
            if let name = scannedName, let url = URL(string: "pushly://u/\(name)") {
                scannedName = nil
                UIApplication.shared.open(url)
            }
        }) {
            QRScannerSheet { text in scannedName = ShareLinks.username(in: text) }
        }
    }
}
