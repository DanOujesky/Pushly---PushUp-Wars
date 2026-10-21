import DesignSystem
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
                    }
                }
                .listRowBackground(Color.clear)

                if let notice = model.notice {
                    Section { InlineBanner(LocalizedStringKey(notice), kind: .info) }.listRowBackground(Color.clear)
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
                                    Text(verbatim: b.opponent.username).typography(TypographyTokens.bodyS)
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
            LiveBattleView(model: LiveBattleModel(battle: battle, service: model.service, sessions: sessions)) {
                model.active = nil
            }
        }
    }
}

/// Live battle (doc 07 §6): camera + my counter, opponent score, timer, then the result.
struct LiveBattleView: View {
    @State var model: LiveBattleModel
    let onClose: () -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .waiting, .done, .cancelled:
                BattleResultView(model: model, onClose: onClose)
            default:
                RepSessionView(model: model.reps) {
                    VStack(spacing: SpacingTokens.s) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: model.battle.opponent.username).typography(TypographyTokens.caption)
                                Text(verbatim: "\(model.battle.theirScore)").typography(TypographyTokens.stat)
                                    .foregroundStyle(Color(ColorTokens.brandVoltText))
                            }
                            .accessibilityElement(children: .combine)
                            Spacer()
                            Text(verbatim: phaseText).typography(TypographyTokens.titleM)
                            Spacer()
                            Button("Leave") { Task { await model.leave() } }.buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
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

struct BattleResultView: View {
    let model: LiveBattleModel
    let onClose: () -> Void

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
                        Text(verbatim: model.battle.opponent.username).typography(TypographyTokens.caption)
                        Text(verbatim: "\(settled ? theirFinal : model.battle.theirScore)").typography(TypographyTokens.displayL)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    }
                }
                if settled, model.battle.ranked, let t = model.battle.myTrophies {
                    Pill(t >= 0 ? "+\(t) trophies" : "\(t) trophies", color: t >= 0 ? ColorTokens.leagueGold : ColorTokens.stateDanger)
                } else if !settled {
                    ProgressView()
                }
            }
            Spacer()
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
