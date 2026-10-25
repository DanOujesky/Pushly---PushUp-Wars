import Core
import CoreImage.CIFilterBuiltins
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
/// friendly), Practice (bots, ghosts) and History open as sheets. Battles open full screen.
public struct BattleHubView: View {
    @State private var model: BattleHubModel
    @AppStorage("battle.mode") private var modeRaw = BattleMode.maxReps.rawValue
    @State private var sheet: HubSheet?
    /// True while a sheet animates away — a battle cover waits for it (two presentations at once get dropped).
    @State private var sheetClosing = false
    private let sessions: SessionServices?
    private let player: BattlePlayer?

    enum HubSheet: String, Identifiable {
        case friends, practice, history, ladder
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
            case .history: HistorySheet(model: model)
            case .ladder: LadderSheet(arena: model.arena)
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
                HubTile(symbol: "cpu", title: "Practice", subtitle: "Bots & ghosts", badge: 0,
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
                AvatarView(username: player.username, presetID: player.avatarPreset, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: player.username)
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .lineLimit(1)
                    if let r = model.arena?.record, r.winStreak > 1 {
                        Text("🔥 \(r.winStreak) win streak")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.brandFlameText))
                    } else {
                        Text("Battle")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Battle").typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
            }
            Spacer()
            if let arena = model.arena {
                Button { sheet = .ladder } label: {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "trophy.fill").foregroundStyle(Color(ColorTokens.leagueGold))
                    Text(verbatim: "\(arena.trophies)")
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                }
                .padding(.horizontal, SpacingTokens.sm)
                .padding(.vertical, SpacingTokens.xs + 2)
                .background(Color.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(ColorTokens.leagueGold).opacity(0.5), lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(arena.trophies) trophies"))
                }
                .buttonStyle(PressDimStyle())
            }
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

/// Full-screen search: you in a ring, the mode, a timer; a bot after 15 s. Only the timer changes.
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
                    AvatarView(username: player.username, presetID: player.avatarPreset, size: 96)
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
                Text("Matched with players near your trophies. Ranked — trophies are on the line.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .multilineTextAlignment(.center)
            }
            SideViewNotice(.compact)
            Spacer()
            if model.waitedS >= 15 {
                SecondaryButton("Nobody yet? Practice vs a bot") { Task { await model.practiceInsteadOfWaiting() } }
            }
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
    @State private var ghost = false

    init(model: BattleHubModel, mode: BattleMode, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _mode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    Picker(selection: $ghost) {
                        Text("Bot 🤖").tag(false)
                        Text("Ghost 👻").tag(true)
                    } label: { Text("Opponent") }
                        .pickerStyle(.segmented)
                    if ghost {
                        Text("Race a recorded run of a real player at your level. 3 a day. If nobody has recorded one yet, you race a bot.")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    } else {
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
                    PrimaryButton(ghost ? "Race a ghost" : "Fight the bot") {
                        onClose()
                        Task {
                            if ghost { await model.ghost(mode) } else { await model.practice(mode, level: level) }
                        }
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

/// Recent battles and past seasons.
struct HistorySheet: View {
    let model: BattleHubModel

    var body: some View {
        NavigationStack {
            List {
                if let r = model.arena?.record {
                    Section {
                        HStack {
                            stat("\(r.wins)", "Wins", ColorTokens.stateSuccessText)
                            stat("\(r.losses)", "Losses", ColorTokens.stateDanger)
                            stat("\(r.bestWinStreak)", "Best streak", ColorTokens.brandFlameText)
                        }
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                }
                Section {
                    if model.history.isEmpty {
                        Text("No battles yet.").foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                    ForEach(model.history) { b in
                        HStack {
                            Text(verbatim: b.winner == "me" ? "W" : b.winner == "opponent" ? "L" : "D")
                                .typography(TypographyTokens.titleS)
                                .foregroundStyle(Color(b.winner == "me" ? ColorTokens.stateSuccessText
                                                      : b.winner == "opponent" ? ColorTokens.stateDanger : ColorTokens.textSecondary))
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(verbatim: b.opponentDisplayName).typography(TypographyTokens.bodyS)
                                Text(verbatim: modeTitle(b.mode, b.variant)).typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.textTertiary))
                            }
                            Spacer()
                            if let t = b.myTrophies, b.ranked {
                                Text(verbatim: t >= 0 ? "+\(t) 🏆" : "\(t) 🏆").typography(TypographyTokens.bodyS)
                                    .foregroundStyle(Color(t >= 0 ? ColorTokens.stateSuccessText : ColorTokens.stateDanger))
                            } else {
                                Text("friendly").typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.textTertiary))
                            }
                        }
                        .frame(minHeight: TouchTarget.minimum)
                        .accessibilityElement(children: .combine)
                    }
                } header: { SectionLabel("Recent battles") }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                if !model.seasons.isEmpty {
                    Section {
                        ForEach(model.seasons) { season in
                            HStack {
                                Text(verbatim: leagueGlyph(season.league)).font(.title2).accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(verbatim: season.month).typography(TypographyTokens.bodyS)
                                    Text("\(leagueTitle(season.league, season.tier)) · best \(season.bestTrophies) 🏆")
                                        .typography(TypographyTokens.caption)
                                        .foregroundStyle(Color(ColorTokens.textTertiary))
                                }
                                Spacer()
                                Text(verbatim: "#\(season.rank)").typography(TypographyTokens.bodyS)
                            }
                            .frame(minHeight: TouchTarget.minimum)
                            .accessibilityElement(children: .combine)
                        }
                    } header: { SectionLabel("Past seasons") }
                        .listRowBackground(Color(ColorTokens.bgSurface))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(ColorTokens.bgBase).ignoresSafeArea())
            .navigationTitle(Text("History"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, _ color: TokenColor) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).typography(TypographyTokens.stat).foregroundStyle(Color(color))
            Text(label).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

    private var link: URL? {
        player.flatMap { URL(string: "https://pushly.app/u/\($0.username)") }
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
                        case "incoming": Pill("Wants to be friends", color: ColorTokens.brandCyan)
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
                        Label("My QR code", systemImage: "qrcode")
                            .typography(TypographyTokens.button)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                    }
                }
                Text("Next to each other? Show your QR code — your friend points their phone camera at it and taps Add.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .sheet(isPresented: $showQR) {
            if let link, let player { QRCodeSheet(url: link, username: player.username) }
        }
    }
}

/// My profile link as a big QR code on white (best for other cameras).
struct QRCodeSheet: View {
    let url: URL
    let username: String

    var body: some View {
        VStack(spacing: SpacingTokens.l) {
            Text("Scan to add me").typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textPrimary))
            if let image = QRCode.image(for: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(SpacingTokens.m)
                    .background(.white, in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                    .accessibilityLabel(Text("QR code for \(username)"))
            }
            Text(verbatim: "@\(username)").typography(TypographyTokens.titleM).foregroundStyle(Color(ColorTokens.brandFlameText))
            Text("Your friend opens the phone camera, points it at the code and taps Add on your profile.")
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .multilineTextAlignment(.center)
        }
        .padding(SpacingTokens.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

enum QRCode {
    /// Black-on-white QR code (CoreImage, medium error correction).
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - League ladder (D-072)

/// Every league from Bronze III to Legend: where you are, how far each step is, floors and what the season end does.
struct LadderSheet: View {
    let arena: ArenaStatus?

    private var trophies: Int { arena?.trophies ?? 0 }
    private var current: LeagueLadder.Rung { LeagueLadder.rung(for: trophies) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section { header }
                        .listRowBackground(Color(ColorTokens.bgSurface))
                    if let targets = arena?.targets, !targets.isEmpty {
                        Section {
                            ForEach(targets) { t in
                                HStack(spacing: SpacingTokens.sm) {
                                    AvatarView(username: t.username, presetID: t.avatarPreset, size: 32)
                                    Text(verbatim: t.username).typography(TypographyTokens.bodyS)
                                    Spacer()
                                    Text(verbatim: "\(t.trophies) 🏆").typography(TypographyTokens.bodyS)
                                    Text(verbatim: "+\(t.gap)").typography(TypographyTokens.caption)
                                        .foregroundStyle(Color(ColorTokens.brandFlameText))
                                }
                                .frame(minHeight: TouchTarget.minimum)
                                .accessibilityElement(children: .combine)
                            }
                        } header: { SectionLabel("Just above you") }
                            .listRowBackground(Color(ColorTokens.bgSurface))
                    }
                    Section {
                        ForEach(LeagueLadder.rungs.reversed()) { rung in
                            row(rung).id(rung.id)
                        }
                    } header: { SectionLabel("All leagues") }
                        .listRowBackground(Color(ColorTokens.bgSurface))
                    Section {
                        VStack(alignment: .leading, spacing: SpacingTokens.s) {
                            Label("Safe floors: once you reach 600, 1,200 or 2,000 trophies in a season, you can't drop below them until it ends.",
                                  systemImage: "shield.lefthalf.filled")
                            Label("Season end (1st of every month): above 2,000 trophies, half of everything over 2,000 is kept. Your best league earns a badge.",
                                  systemImage: "calendar")
                            Label("Only Quick match moves trophies. Friends, bots and ghosts never do.", systemImage: "bolt.fill")
                        }
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                    } header: { SectionLabel("How it works") }
                        .listRowBackground(Color(ColorTokens.bgSurface))
                }
                .scrollContentBackground(.hidden)
                .background(Color(ColorTokens.bgBase).ignoresSafeArea())
                .navigationTitle(Text("Leagues"))
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { proxy.scrollTo(current.id, anchor: .center) }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(spacing: SpacingTokens.m) {
            Text(verbatim: leagueGlyph(current.league))
                .font(.system(size: 44))
                .frame(width: 64, height: 64)
                .background(Color(leagueColor(current.league)).opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: leagueTitle(current.league, current.tier))
                    .typography(TypographyTokens.titleM)
                    .foregroundStyle(Color(leagueColor(current.league)))
                Text("\(trophies) trophies").typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                if let arena {
                    Text("Best ever: \(arena.bestTrophies)").typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                    if let rank = arena.rank {
                        Text("#\(rank) in the world").typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.brandFlameText))
                    }
                }
            }
        }
        .padding(.vertical, SpacingTokens.xs)
        .accessibilityElement(children: .combine)
    }

    private func row(_ rung: LeagueLadder.Rung) -> some View {
        let isCurrent = rung == current
        let reached = rung.from <= trophies
        return HStack(spacing: SpacingTokens.sm) {
            Text(verbatim: leagueGlyph(rung.league)).font(.title3).accessibilityHidden(true)
                .opacity(reached ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: leagueTitle(rung.league, rung.tier))
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(isCurrent ? leagueColor(rung.league) : reached ? ColorTokens.textPrimary : ColorTokens.textTertiary))
                HStack(spacing: SpacingTokens.xs) {
                    Text(verbatim: rung.to.map { "\(rung.from)–\($0) 🏆" } ?? "\(rung.from)+ 🏆")
                    if LeagueLadder.floors.contains(rung.from) {
                        Text("· safe floor")
                    }
                }
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
                if isCurrent, let to = rung.to {
                    GradientProgressBar(value: Double(trophies - rung.from) / Double(max(to + 1 - rung.from, 1)), height: 6)
                        .padding(.top, 2)
                }
            }
            Spacer()
            if isCurrent {
                Pill("You", color: ColorTokens.brandFlameText)
            } else if reached {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(ColorTokens.stateSuccessText))
                    .accessibilityLabel(Text("Reached"))
            } else {
                Text(verbatim: "+\(rung.from - trophies)")
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .accessibilityLabel(Text("\(rung.from - trophies) trophies to go"))
            }
        }
        .frame(minHeight: TouchTarget.minimum)
        .listRowBackground(isCurrent ? Color(leagueColor(rung.league)).opacity(0.14) : Color(ColorTokens.bgSurface))
        .accessibilityElement(children: .combine)
    }
}
