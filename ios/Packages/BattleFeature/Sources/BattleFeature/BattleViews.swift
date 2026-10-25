import Core
import DesignSystem
import LiveKit
import SwiftUI
import WakeFlowFeature

func modeTitle(_ mode: String, _ variant: [String: Int] = [:]) -> String {
    switch mode {
    case "max_reps": String(localized: "Max reps \(variant["durationS"] ?? 60) s")
    case "speed": String(localized: "Speed to \(variant["targetReps"] ?? 20)")
    case "endurance": String(localized: "Endurance")
    case "best_of_3": String(localized: "Best of 3")
    case "turns": String(localized: "Turns")
    default: mode
    }
}

/// Battle tab (doc 07): quick match, challenges, history. Battles open full screen.
public struct BattleHubView: View {
    @State private var model: BattleHubModel
    @State private var challengeMode: BattleMode = .maxReps
    @State private var ranked = false
    @State private var botLevel: BotLevel = .rookie
    private let sessions: SessionServices?

    public init(model: BattleHubModel, sessions: SessionServices?) {
        _model = State(initialValue: model)
        self.sessions = sessions
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: SpacingTokens.m) {
                        ScreenTitle("Battle", token: TypographyTokens.displayM)
                        Text("Same time, same rules, every rep checked by the camera.")
                            .typography(TypographyTokens.body)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                        SideViewNotice(.card)
                    }
                }
                .listRowBackground(Color.clear)

                if let notice = model.notice {
                    Section {
                        InlineBanner(LocalizedStringKey(notice), kind: .info)
                        if model.botOffer != nil {
                            PrimaryButton("Practice vs a bot instead") { Task { await model.practiceInsteadOfWaiting() } }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    if let mode = model.queuedMode {
                        HStack {
                            ProgressView()
                            Text("Finding an opponent for \(modeTitle(mode.rawValue, mode.variant))… \(model.waitedS) s")
                            Spacer()
                            Button("Cancel") { Task { await model.cancelQueue() } }
                        }
                        .frame(minHeight: TouchTarget.minimum)
                        if model.waitedS >= 15 {
                            Button {
                                Task { await model.practiceInsteadOfWaiting() }
                            } label: {
                                Label("Nobody yet? Practice vs a bot", systemImage: "cpu")
                                    .frame(minHeight: TouchTarget.minimum)
                            }
                        }
                    } else {
                        ForEach(BattleMode.allCases.filter(\.quickMatch)) { mode in
                            Button {
                                Task { await model.quickMatch(mode) }
                            } label: {
                                Label(modeTitle(mode.rawValue, mode.variant), systemImage: "bolt.fill")
                                    .frame(minHeight: TouchTarget.minimum)
                            }
                        }
                    }
                } header: {
                    SectionLabel("Quick match (ranked)")
                }
                .listRowBackground(Color(ColorTokens.bgSurface))

                Section {
                    ForEach(BattleMode.allCases.filter(\.quickMatch)) { mode in
                        Button {
                            Task { await model.ghost(mode) }
                        } label: {
                            Label(modeTitle(mode.rawValue, mode.variant), systemImage: "figure.run")
                                .frame(minHeight: TouchTarget.minimum)
                        }
                    }
                } header: {
                    SectionLabel("Ghost battle (practice)")
                } footer: {
                    Text("Race a recorded run of a player at your level. No trophies, 3 a day. If nobody has recorded one yet, you race a bot.")
                        .typography(TypographyTokens.caption)
                }
                .listRowBackground(Color(ColorTokens.bgSurface))

                Section {
                    Picker("Bot level", selection: $botLevel) {
                        ForEach(BotLevel.allCases) { level in
                            Text(verbatim: "\(level.title) · \(level.pace)").tag(level)
                        }
                    }
                    .frame(minHeight: TouchTarget.minimum)
                    ForEach(BattleMode.allCases.filter(\.quickMatch)) { mode in
                        Button {
                            Task { await model.practice(mode, level: botLevel) }
                        } label: {
                            Label(modeTitle(mode.rawValue, mode.variant), systemImage: "cpu")
                                .frame(minHeight: TouchTarget.minimum)
                        }
                    }
                } header: {
                    SectionLabel("Practice vs bot 🤖")
                } footer: {
                    Text("Computer opponents, always marked with 🤖. XP only — no trophies, no leaderboard.")
                        .typography(TypographyTokens.caption)
                }
                .listRowBackground(Color(ColorTokens.bgSurface))

                if !model.invites.incoming.isEmpty {
                    Section {
                        ForEach(model.invites.incoming) { inv in
                            HStack {
                                AvatarView(username: inv.from.username, presetID: inv.from.avatarPreset, size: 36)
                                VStack(alignment: .leading) {
                                    Text(verbatim: inv.from.username).typography(TypographyTokens.titleS)
                                    Text(verbatim: modeTitle(inv.mode, inv.variant) + (inv.ranked ? " · " + String(localized: "ranked") : ""))
                                        .typography(TypographyTokens.caption)
                                }
                                Spacer()
                                Button("Fight") { Task { await model.accept(inv) } }
                                    .buttonStyle(.borderedProminent).tint(Color(ColorTokens.brandFlame))
                                Button("No") { Task { await model.decline(inv) } }.buttonStyle(.bordered)
                            }
                            .frame(minHeight: TouchTarget.minimum)
                        }
                    } header: {
                        SectionLabel("Challenges for you")
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                }

                Section {
                    Picker("Mode", selection: $challengeMode) {
                        ForEach(BattleMode.allCases) { Text(modeTitle($0.rawValue, $0.variant)).tag($0) }
                    }
                    Toggle("Ranked (trophies, max 3 a day per friend)", isOn: $ranked).tint(Color(ColorTokens.brandFlame))
                    if model.friends.isEmpty {
                        Text("Add friends on your profile to challenge them.").foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                    ForEach(model.friends) { friend in
                        Button {
                            Task { await model.challenge(friend, mode: challengeMode, ranked: ranked) }
                        } label: {
                            HStack {
                                AvatarView(username: friend.username, presetID: friend.avatarPreset, size: 32)
                                Text(verbatim: friend.username)
                                Spacer()
                                Image(systemName: "bolt.horizontal.fill").accessibilityHidden(true)
                            }
                            .frame(minHeight: TouchTarget.minimum)
                        }
                    }
                } header: {
                    SectionLabel("Challenge a friend")
                }
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
                    } header: {
                        SectionLabel("Past seasons")
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                }

                if !model.history.isEmpty {
                    Section {
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
                                }
                                Spacer()
                                if let t = b.myTrophies, b.ranked {
                                    Text(verbatim: t >= 0 ? "+\(t) 🏆" : "\(t) 🏆").typography(TypographyTokens.bodyS)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        SectionLabel("History")
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await model.load() }
            .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -260))
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .task { await model.load() }
        .fullScreenCover(item: $model.active, onDismiss: { Task { await model.load() } }) { battle in
            LiveBattleView(model: LiveBattleModel(battle: battle, service: model.service, sessions: sessions),
                           onClose: { model.active = nil },
                           onRematch: { finished in
                               model.active = nil
                               Task { await model.rematch(finished) }
                           })
        }
    }
}

/// Live battle (doc 07 §6): camera + my counter, opponent score, timer, then the result.
struct LiveBattleView: View {
    @State var model: LiveBattleModel
    let onClose: () -> Void
    var onRematch: ((Battle) -> Void)?

    var body: some View {
        Group {
            switch model.phase {
            case .waiting, .done, .cancelled:
                BattleResultView(model: model, onClose: onClose, onRematch: onRematch)
            default:
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        if let track = model.video.remoteTrack {
                            OpponentVideo(track: track, name: model.battle.opponentDisplayName, score: model.battle.theirScore)
                                .frame(height: geo.size.height * 0.42)
                        }
                        session
                    }
                }
                .background(Color.black)
                .overlay { CalloutFlash(callout: model.callout) }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var session: some View {
        RepSessionView(model: model.reps) {
            VStack(spacing: SpacingTokens.s) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: model.battle.opponentDisplayName).typography(TypographyTokens.caption)
                        Text(verbatim: "\(model.battle.theirScore)").typography(TypographyTokens.stat)
                            .foregroundStyle(Color(ColorTokens.brandVoltText))
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    Text(verbatim: phaseText).typography(TypographyTokens.titleM)
                    Spacer()
                    if model.video.state == .connected {
                        Button {
                            Task { await model.video.toggleCamera() }
                        } label: {
                            Image(systemName: model.video.cameraOn ? "video.fill" : "video.slash.fill")
                                .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                        }
                        .accessibilityLabel(Text(model.video.cameraOn ? "Stop sharing my camera" : "Share my camera"))
                    }
                    Button("Leave") { Task { await model.leave() } }.buttonStyle(.bordered)
                }
                if model.phase == .live, let lead = model.lead {
                    LeadBar(mine: lead.mine, theirs: lead.theirs, opponent: model.battle.opponentDisplayName)
                }
                if model.phase == .live {
                    ModeHud(model: model)
                } else {
                    SideViewNotice(.compact)
                        .padding(SpacingTokens.s)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: RadiusTokens.s))
                }
            }
        }
    }

    private var phaseText: String {
        switch model.phase {
        case .lobby: String(localized: "Get into position")
        case let .countdown(n): "\(n)"
        case .live: model.secondsLeft.map { "\($0) s" } ?? String(localized: "GO")
        default: ""
        }
    }
}

/// Tug of war (D-066): who leads and by how much, at a glance — my share of the reps fills from the left.
struct LeadBar: View {
    let mine: Int
    let theirs: Int
    let opponent: String

    private var diff: Int { mine - theirs }
    private var share: Double {
        let total = mine + theirs
        return total == 0 ? 0.5 : Double(mine) / Double(total)
    }

    var body: some View {
        VStack(spacing: SpacingTokens.xs) {
            Text(verbatim: diff > 0 ? "+\(diff)" : diff < 0 ? "−\(-diff)" : "=")
                .typography(TypographyTokens.displayM)
                .foregroundStyle(Color(diff > 0 ? ColorTokens.stateSuccess : diff < 0 ? ColorTokens.stateDanger : ColorTokens.textPrimary))
                .contentTransition(.numericText())
                .animation(.spring(duration: MotionTokens.popSeconds), value: diff)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(ColorTokens.brandVolt))
                    Capsule().fill(Color(ColorTokens.brandFlame))
                        .frame(width: max(12, geo.size.width * share))
                        .animation(.spring(duration: MotionTokens.baseSeconds), value: share)
                    Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2).offset(x: geo.size.width / 2 - 1)
                }
            }
            .frame(height: 14)
            HStack {
                Text("You \(mine)").typography(TypographyTokens.caption)
                Spacer()
                Text(verbatim: "\(theirs) \(opponent)").typography(TypographyTokens.caption)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(diff > 0 ? "You lead by \(diff)" : diff < 0 ? "You're \(-diff) behind" : "Level"))
    }
}

/// The announcer's line, big for a moment (D-066).
struct CalloutFlash: View {
    let callout: (text: String, positive: Bool, id: Int)?
    @State private var shown: (text: String, positive: Bool)?
    @State private var shownId = 0

    var body: some View {
        ZStack {
            if let shown {
                Text(verbatim: shown.text.uppercased())
                    .typography(TypographyTokens.displayM)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(shown.positive ? ColorTokens.stateSuccess : ColorTokens.stateDanger))
                    .shadow(color: .black.opacity(0.7), radius: 10)
                    .padding(SpacingTokens.l)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: callout?.id) { _, _ in
            guard let callout else { return }
            withAnimation(.spring(duration: MotionTokens.popSeconds)) { shown = (callout.text, callout.positive) }
            let id = callout.id
            shownId = id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1400))
                if shownId == id { withAnimation(.easeOut(duration: MotionTokens.fastSeconds)) { shown = nil } }
            }
        }
    }
}

/// The opponent's camera (top half, doc 07 §6) with their name and live score.
struct OpponentVideo: View {
    let track: Track & VideoTrackProtocol
    let name: String
    let score: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: .off)
                .accessibilityLabel(Text("\(name)'s camera"))
            HStack {
                Text(verbatim: name).typography(TypographyTokens.labelDisplay)
                Spacer()
                Text(verbatim: "\(score)").typography(TypographyTokens.stat)
                    .foregroundStyle(Color(ColorTokens.brandVoltText))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: MotionTokens.popSeconds), value: score)
            }
            .foregroundStyle(.white)
            .padding(SpacingTokens.m)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        }
        .clipped()
    }
}

/// Mode-specific HUD line (doc 07 §6): round dots + set/rest for Best of 3, whose turn + 5 s window for Turns.
struct ModeHud: View {
    let model: LiveBattleModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            if let t = model.elapsedMs {
                switch model.mode {
                case "best_of_3": bo3(t)
                case "turns": turns(t)
                default: EmptyView()
                }
            }
        }
    }

    private func bo3(_ t: Int64) -> some View {
        let clock = BattleHud.bo3Clock(t)
        let mine = BattleHud.mySets(model.myReps)
        let theirs = model.battle.theirRounds
        return VStack(spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.s) {
                ForEach(0..<3, id: \.self) { r in
                    let done = r < clock.round || clock.phase == "rest" && r == clock.round || clock.phase == "over"
                    let my = r < mine.count ? mine[r] : 0
                    let their = r < theirs.count ? theirs[r] : 0
                    Circle()
                        .fill(Color(!done ? ColorTokens.strokeStrong
                                    : my > their ? ColorTokens.stateSuccess : my < their ? ColorTokens.stateDanger
                                    : ColorTokens.textTertiary))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(ColorTokens.textPrimary), lineWidth: r == clock.round && !done ? 2 : 0))
                }
            }
            .accessibilityHidden(true)
            Text(bo3Text(clock))
                .typography(TypographyTokens.labelDisplay)
                .foregroundStyle(Color(clock.phase == "rest" ? ColorTokens.brandCyan : ColorTokens.textPrimary))
        }
        .accessibilityElement(children: .combine)
    }

    private func bo3Text(_ clock: BattleHud.Bo3Clock) -> String {
        let s = Int((clock.msLeft + 999) / 1000)
        switch clock.phase {
        case "rest": return String(localized: "Rest · round \(clock.round + 2) in \(s) s")
        case "set" where model.bo3SetOver: return String(localized: "Set over · wait for the next round")
        case "set": return String(localized: "Round \(clock.round + 1) of 3 · one set · \(s) s")
        default: return ""
        }
    }

    private func turns(_ t: Int64) -> some View {
        let state = model.turn(t)
        let left = max(0, Double(state?.msLeft ?? 0) / 1000)
        let text: String = switch state?.turn {
        case "me": String(localized: "Your turn · \(String(format: "%.1f", left)) s")
        case "them": String(localized: "Their turn · hold the plank")
        default: String(localized: "Anyone can start — do one rep")
        }
        return HStack(spacing: SpacingTokens.s) {
            if state?.turn == "me" {
                ProgressView(value: min(1, left / 5))
                    .tint(Color(left < 2 ? ColorTokens.stateDanger : ColorTokens.brandFlame))
                    .frame(width: 80)
                    .accessibilityHidden(true)
            }
            Text(text)
                .typography(TypographyTokens.labelDisplay)
                .foregroundStyle(Color(state?.turn == "me" ? ColorTokens.brandFlameText : ColorTokens.textSecondary))
        }
        .accessibilityElement(children: .combine)
    }
}

struct BattleResultView: View {
    let model: LiveBattleModel
    let onClose: () -> Void
    var onRematch: ((Battle) -> Void)?

    private var settled: Bool { model.battle.status == "settled" }

    var body: some View {
        let won = model.battle.winner == "me"
        let lost = model.battle.winner == "opponent"
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            Spacer()
            if model.phase == .cancelled {
                SectionLabel("Battle cancelled")
                Text("Nobody lost trophies.").typography(TypographyTokens.body)
            } else {
                SectionLabel(!settled ? "Checking the result…" : won ? "Victory" : lost ? "Defeat" : "Draw",
                             color: won ? ColorTokens.stateSuccessText : ColorTokens.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: SpacingTokens.l) {
                    VStack(alignment: .leading) {
                        Text("You").typography(TypographyTokens.caption)
                        Text(verbatim: "\(settled ? myFinal : model.myReps.count)").typography(TypographyTokens.displayCounter)
                    }
                    VStack(alignment: .leading) {
                        Text(verbatim: model.battle.opponentDisplayName).typography(TypographyTokens.caption)
                        Text(verbatim: "\(settled ? theirFinal : model.battle.theirScore)").typography(TypographyTokens.displayL)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    }
                }
                if settled, let r = model.battle.result, let ra = r.a.rounds, let rb = r.b.rounds {
                    let mine = model.battle.me == "a" ? ra : rb
                    let theirs = model.battle.me == "a" ? rb : ra
                    Text("Rounds \(mine)–\(theirs)").typography(TypographyTokens.titleM)
                }
                if settled, model.battle.result?.reason == "turn_missed" {
                    Text(model.battle.winner == "me" ? "They missed their turn." : "You missed your turn.")
                        .typography(TypographyTokens.body)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                }
                if settled, model.battle.ranked, let t = model.battle.myTrophies {
                    Pill(t >= 0 ? "+\(t) trophies" : "\(t) trophies", color: t >= 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger)
                } else if !settled {
                    ProgressView()
                }
            }
            Spacer()
            if settled, model.battle.ghost != true, Reporter.isAvailable {
                ReportButton("Report opponent") { reason in await Reporter.send(.battle(model.battle.id), reason: reason) }
                    .frame(minHeight: TouchTarget.minimum)
            }
            if settled, let onRematch,
               (["friendly", "friend_ranked"].contains(model.battle.type) && model.battle.opponent.id != nil) || model.battle.bot != nil {
                SecondaryButton("Rematch") { onRematch(model.battle) }
            }
            PrimaryButton("Done", action: onClose)
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: won ? ColorTokens.leagueGold : ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -200))
    }

    private var myFinal: Int {
        guard let r = model.battle.result else { return model.myReps.count }
        return model.battle.me == "a" ? r.a.reps : r.b.reps
    }

    private var theirFinal: Int {
        guard let r = model.battle.result else { return model.battle.theirScore }
        return model.battle.me == "a" ? r.b.reps : r.a.reps
    }
}

func leagueGlyph(_ league: String) -> String {
    switch league {
    case "bronze": "🥉"
    case "silver": "🥈"
    case "gold": "🥇"
    case "platinum": "💠"
    case "diamond": "💎"
    case "champion": "🏆"
    default: "👑"
    }
}

func leagueTitle(_ league: String, _ tier: String?) -> String {
    let name: String = switch league {
    case "bronze": String(localized: "Bronze")
    case "silver": String(localized: "Silver")
    case "gold": String(localized: "Gold")
    case "platinum": String(localized: "Platinum")
    case "diamond": String(localized: "Diamond")
    case "champion": String(localized: "Champion")
    default: String(localized: "Legend")
    }
    return tier.map { "\(name) \($0)" } ?? name
}
