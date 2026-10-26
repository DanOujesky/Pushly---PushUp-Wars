import Core
import DesignSystem
import SwiftUI

/// Clan tab (doc 09 §4, D-074): a game lobby on one screen, like the Battle tab. In a clan: the clan's badge, the
/// war arena (us vs them), your push-ups for the clan today, a big PUSH button and tiles for members, chat and
/// history. Without a clan: find or create one. Everything else opens as a sheet. Static — nothing moves (D-072).
public struct ClanTabView: View {
    @State private var model: ClanModel
    private let training: ((@escaping () -> Void) -> AnyView)?

    public init(model: ClanModel, training: ((@escaping () -> Void) -> AnyView)? = nil) {
        _model = State(initialValue: model)
        self.training = training
    }

    public var body: some View {
        Group {
            if !model.loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let home = model.home {
                ClanLobbyView(model: model, home: home, training: training)
            } else {
                ClanJoinLobbyView(model: model)
            }
        }
        .background { ClanBackdrop(color: model.home.map { badgeColor($0.summary) } ?? ColorTokens.brandCyan) }
        .overlay(alignment: .top) { ClanToast(model: model) }
        .task { await model.load() }
    }
}

func badgeColor(_ clan: ClanSummary) -> TokenColor {
    Cosmetics.badgeColor((clan.badge ?? ClanBadgeStyle()).resolved(tag: clan.tag).color)
}

// MARK: - Lobby (in a clan)

enum ClanSheet: String, Identifiable {
    case members, chat, history, war, settings, profile
    var id: String { rawValue }
}

struct ClanLobbyView: View {
    let model: ClanModel
    let home: ClanHome
    let training: ((@escaping () -> Void) -> AnyView)?
    @State private var sheet: ClanSheet?
    @State private var showTraining = false
    @State private var result: ClanWar?

    private var role: ClanRole { model.myRole ?? .member }

    var body: some View {
        ViewThatFits(in: .vertical) {
            lobby
            ScrollView { lobby }.scrollIndicators(.hidden)
        }
        .refreshable { await model.load() }
        .sheet(item: $sheet) { which in
            switch which {
            case .members: ClanMembersSheet(model: model) { sheet = nil }
            case .chat: NavigationStack { ClanChatView(model: model) }
            case .history: WarHistorySheet(model: model)
            case .war: WarDetailsSheet(model: model)
            case .settings: ClanSettingsSheet(model: model) { sheet = nil }
            case .profile:
                NavigationStack {
                    ClanProfileView(model: model, clanId: home.summary.id)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
                        .clanRoutes(model)
                }
            }
        }
        .fullScreenCover(isPresented: $showTraining, onDismiss: { Task { await model.load() } }) {
            if let training { training { showTraining = false } }
        }
        // Sunday results first, then the next lobby (D-078)
        .fullScreenCover(item: $result) { war in
            WarResultView(war: war, onContinue: {
                WarResultSeen.mark(war.id)
                result = nil
            }, model: model)
        }
        .task(id: home.war?.isLive == true) { await LiveWarPoll.run(model) }
        .task(id: home.warState?.last?.id) {
            if let last = home.warState?.last, !WarResultSeen.contains(last.id) { result = last }
        }
    }

    private var lobby: some View {
        VStack(spacing: SpacingTokens.m) {
            topBar
            Spacer(minLength: SpacingTokens.xs)
            Button { sheet = home.war == nil ? .members : .war } label: {
                if let war = home.war {
                    WarCard(war: war)
                } else {
                    ClanIdleHero(summary: home.summary)
                }
            }
            .buttonStyle(PressDim())
            .accessibilityHint(home.war == nil ? Text("Shows the members") : Text("Shows the war details"))
            if let war = home.war, war.isLive, let rally = war.rally {
                RallyButton(available: rally.available, behind: war.gap < 0) { Task { await model.rally() } }
            }
            Spacer(minLength: SpacingTokens.xs)
            if let war = home.war, war.isLive {
                MyWarDay(today: war.myToday)
            }
            if training != nil {
                if let war = home.war, war.isLive {
                    PushButton() { showTraining = true }
                } else {
                    // D-080: nothing counts for the clan outside a live war — say when it starts instead
                    WarNotLiveButton(startsAt: home.war?.startsAt)
                }
            }
            tiles
        }
        .padding(.horizontal, SpacingTokens.gutter)
        .padding(.top, SpacingTokens.s)
        .padding(.bottom, SpacingTokens.m)
    }

    private var topBar: some View {
        HStack(spacing: SpacingTokens.sm) {
            Button { sheet = .profile } label: {
                HStack(spacing: SpacingTokens.sm) {
                    ClanEmblemView(style: home.summary.badge, tag: home.summary.tag, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: home.summary.name)
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .lineLimit(1)
                        Text(verbatim: "\(roleTitle(role).capitalized) · \(home.summary.memberCount)/30")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressDim())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Shows the clan page"))
            Spacer()
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(Color(badgeColor(home.summary)))
                Text(verbatim: "\(home.summary.rating)")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
            }
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.xs + 2)
            .background(Color.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(badgeColor(home.summary)).opacity(0.5), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Clan rating \(home.summary.rating)"))
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
            }
            .accessibilityLabel(Text("Clan settings"))
        }
        .frame(minHeight: TouchTarget.minimum)
    }

    private var tiles: some View {
        let requests = role.canAcceptRequests ? home.requests.count : 0
        return HStack(spacing: SpacingTokens.s) {
            LobbyTile(symbol: "person.3.fill", title: "Members", subtitle: "\(home.summary.memberCount)/30",
                      badge: requests, tint: ColorTokens.brandCyan) { sheet = .members }
            LobbyTile(symbol: "bubble.left.and.bubble.right.fill", title: "Chat", subtitle: "Clan talk",
                      badge: 0, tint: ColorTokens.brandLime) { sheet = .chat }
            LobbyTile(symbol: "flag.checkered", title: "Wars", subtitle: warRecord,
                      badge: 0, tint: ColorTokens.brandVolt) { sheet = .history }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var warRecord: LocalizedStringKey {
        let w = model.warHistory.filter { $0.letter == "W" }.count
        let l = model.warHistory.filter { $0.letter == "L" }.count
        return model.warHistory.isEmpty ? "History" : "\(w) W · \(l) L"
    }
}

/// Our share of the points vs theirs, split where the scores meet.
struct TugBar: View {
    let us: Int
    let them: Int
    let ours: Color
    let theirs: Color

    var body: some View {
        GeometryReader { geo in
            let total = max(us + them, 1)
            let share = us + them == 0 ? 0.5 : CGFloat(us) / CGFloat(total)
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [theirs.opacity(0.7), theirs], startPoint: .leading, endPoint: .trailing))
                Capsule().fill(LinearGradient(colors: [ours, ours.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.height, geo.size.width * share))
                Rectangle().fill(.white).frame(width: 3)
                    .offset(x: min(max(geo.size.width * share - 1.5, 0), geo.size.width - 3))
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .accessibilityHidden(true)
    }
}

/// War switched off: the clan badge big.
struct ClanIdleHero: View {
    let summary: ClanSummary

    var body: some View {
        VStack(spacing: SpacingTokens.sm) {
            ClanEmblemView(style: summary.badge, tag: summary.tag, size: 120)
            Text(verbatim: summary.name).typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textPrimary))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("Clan Wars are off for this clan. Leaders can switch them on in the clan settings.")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !summary.description.isEmpty {
                Text(verbatim: summary.description)
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Today's push-ups for the clan with the full / half-points caps.
struct MyWarDay: View {
    let today: ClanWar.Today

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack {
                Text("You today").typography(TypographyTokens.labelDisplay).foregroundStyle(Color(ColorTokens.textSecondary))
                Spacer()
                Text("+\(today.counted) points").typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.brandFlameText))
            }
            GradientProgressBar(value: today.fullCap > 0 ? min(1, Double(today.raw) / Double(today.fullCap)) : 0, height: 8)
            Text(today.raw < today.fullCap ? "Full points up to \(today.fullCap) push-ups, half up to \(today.halfCap). Side view only."
                                           : "Full points reached — half points up to \(today.halfCap). Side view only.")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The big call to action: push-ups for the clan (free training; side view counts for the war).
struct PushButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("PUSH FOR THE CLAN")
                    .typography(TypographyTokens.displayM)
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Side view counts for the war")
                    .typography(TypographyTokens.overline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(LinearGradient(GradientTokens.hero), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
            .shadow(color: Color(ColorTokens.brandFlame).opacity(0.45), radius: 18, y: 6)
        }
        .buttonStyle(PressDim())
    }
}

/// The PUSH button outside a live war: greyed out, not tappable, with the time until the war starts.
struct WarNotLiveButton: View {
    let startsAt: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let left = startsAt.flatMap { WarClock.until($0, now: context.date) }
            VStack(spacing: 2) {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "lock.fill").accessibilityHidden(true)
                    Text(left.map { "CLAN WAR STARTS IN \($0)" } ?? (startsAt == nil ? "CLAN WARS ARE OFF" : "CLAN WAR STARTS SOON"))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .typography(TypographyTokens.titleM)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                Text(startsAt == nil ? "Leaders can switch them on in the clan settings"
                                     : "Push-ups count for the clan only during the war — Monday 00:00 UTC")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, SpacingTokens.m)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color(ColorTokens.bgSurface).opacity(0.85), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
                .strokeBorder(Color(ColorTokens.strokeSubtle), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

struct RallyButton: View {
    let available: Bool
    let behind: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(available ? "Rally the clan" : "Rally used — back in a few hours", systemImage: "megaphone.fill")
                .typography(TypographyTokens.titleS)
                .foregroundStyle(Color(available ? ColorTokens.textPrimary : ColorTokens.textTertiary))
                .padding(.horizontal, SpacingTokens.m)
                .frame(minHeight: TouchTarget.minimum)
                .background(Color(available ? (behind ? ColorTokens.stateDanger : ColorTokens.brandFlame) : ColorTokens.bgSurface)
                    .opacity(available ? 0.85 : 0.7), in: Capsule())
        }
        .buttonStyle(PressDim())
        .disabled(!available)
    }
}

/// Pressed = slightly dimmed, nothing moves.
struct PressDim: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Equal-sized tile under the push button.
struct LobbyTile: View {
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(tint))
                    .frame(height: 26)
                Text(title)
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 88)
            .background(Color(ColorTokens.bgSurface).opacity(0.9), in: RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous).strokeBorder(Color(tint).opacity(0.35), lineWidth: 1))
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
        .buttonStyle(PressDim())
        .accessibilityElement(children: .combine)
        .accessibilityHint(badge > 0 ? Text("\(badge) waiting") : Text(""))
    }
}

/// Dark arena with a glow in the clan's colour and faint floor lines.
struct ClanBackdrop: View {
    let color: TokenColor

    var body: some View {
        ZStack {
            Color(ColorTokens.bgBase)
            RadialGradient(colors: [Color(color).opacity(0.3), .clear], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 10, endRadius: 380)
            Canvas { ctx, size in
                let horizon = size.height * 0.6
                for i in 0..<9 {
                    let t = CGFloat(i) / 8
                    var p = Path()
                    p.move(to: CGPoint(x: size.width / 2, y: horizon))
                    p.addLine(to: CGPoint(x: size.width * (t * 1.6 - 0.3), y: size.height))
                    ctx.stroke(p, with: .color(.white.opacity(0.035)), lineWidth: 1)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ClanToast: View {
    let model: ClanModel

    var body: some View {
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

// MARK: - Lobby without a clan

struct ClanJoinLobbyView: View {
    let model: ClanModel
    @State private var discovering = false
    @State private var creating = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.hidden)
        }
        .sheet(isPresented: $discovering) { ClanDiscoverySheet(model: model) }
        .sheet(isPresented: $creating) { CreateClanView(model: model) { creating = false } }
    }

    private var content: some View {
        VStack(spacing: SpacingTokens.m) {
            HStack {
                Text("Clans").typography(TypographyTokens.displayM).foregroundStyle(Color(ColorTokens.textPrimary))
                Spacer()
            }
            .frame(minHeight: TouchTarget.minimum)
            Spacer(minLength: SpacingTokens.s)
            ZStack {
                ClanEmblemView(style: ClanBadgeStyle(shape: "shield", color: "cyan", emblem: "fist"), tag: "", size: 130)
                    .opacity(0.9)
            }
            VStack(spacing: SpacingTokens.s) {
                Text("Join a clan").typography(TypographyTokens.displayL).foregroundStyle(Color(ColorTokens.textPrimary))
                Text("Team up with up to 30 people. Every side-view push-up you do counts in the weekly Clan War.")
                    .typography(TypographyTokens.body)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: SpacingTokens.s) {
                perk("flag.checkered", "A new Clan War every Monday — your clan vs another")
                perk("person.3.fill", "Clans are matched with clans of similar size and strength")
                perk("bubble.left.and.bubble.right.fill", "Clan chat, rallies and a badge you design together")
            }
            .padding(SpacingTokens.m)
            .background(Color(ColorTokens.bgSurface).opacity(0.85), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
            Spacer(minLength: SpacingTokens.s)
            if let notice = model.notice { InlineBanner(LocalizedStringKey(notice), kind: .info) }
            Button { discovering = true } label: {
                VStack(spacing: 0) {
                    Text("FIND A CLAN").typography(TypographyTokens.displayM).foregroundStyle(.white)
                    Text("Join one in seconds").typography(TypographyTokens.overline).foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(LinearGradient(GradientTokens.hero), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: Color(ColorTokens.brandFlame).opacity(0.45), radius: 18, y: 6)
            }
            .buttonStyle(PressDim())
            SecondaryButton("Create a clan") { creating = true }
        }
        .padding(.horizontal, SpacingTokens.gutter)
        .padding(.top, SpacingTokens.s)
        .padding(.bottom, SpacingTokens.m)
    }

    private func perk(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: symbol).foregroundStyle(Color(ColorTokens.brandCyan)).frame(width: 24).accessibilityHidden(true)
            Text(text).typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct ClanDiscoverySheet: View {
    @Bindable var model: ClanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let notice = model.notice {
                    Section { InlineBanner(LocalizedStringKey(notice), kind: .info) }.listRowBackground(Color.clear)
                }
                Section {
                    if model.results.isEmpty {
                        Text("No clans found.").foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                    ForEach(model.results) { clan in
                        ClanResultRow(clan: clan, busy: model.busy) { Task { await model.join(clan) } }
                    }
                } header: {
                    SectionLabel(model.query.isEmpty ? "Recommended" : "Results")
                }
                .listRowBackground(Color(ColorTokens.bgSurface))
                // clan discovery only — never in the clan chat (doc 13 §1)
                Section { AdBannerSlot("clan_banner") }
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .arenaBackground(glow: ColorTokens.brandCyan, alignment: .top, offset: CGSize(width: 0, height: -260))
            .searchable(text: $model.query, prompt: Text("Clan name"))
            .onChange(of: model.query) { Task { await model.search() } }
            .refreshable { await model.search() }
            .task { await model.search() }
            .navigationTitle(Text("Find a clan"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: model.home?.summary.id) { _, id in if id != nil { dismiss() } }
        }
    }
}

struct ClanResultRow: View {
    let clan: ClanSummary
    let busy: Bool
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: SpacingTokens.m) {
            ClanEmblemView(style: clan.badge, tag: clan.tag, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: clan.name).typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text("\(clan.memberCount)/\(clan.maxMembers) members · rating \(clan.rating)")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if clan.requested {
                Pill("Requested")
            } else if clan.joinPolicy != "invite_only", clan.memberCount < clan.maxMembers {
                Button(clan.joinPolicy == "open" ? "Join" : "Ask", action: onJoin)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(ColorTokens.brandFlame))
                    .disabled(busy)
            }
        }
        .frame(minHeight: TouchTarget.minimum)
    }
}

// MARK: - Create / settings

struct CreateClanView: View {
    let model: ClanModel
    let onDone: () -> Void
    @State private var name = ""
    @State private var about = ""
    @State private var policy = "open"
    @State private var badge = ClanBadgeStyle(shape: "shield", color: "flame", emblem: "flame")

    var body: some View {
        NavigationStack {
            Form {
                Section { BadgeEditor(style: $badge, tag: name.isEmpty ? "?" : name) } header: { SectionLabel("Badge") }
                Section {
                    TextField("Name (3–24)", text: $name)
                    TextField("Description", text: $about, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Picker("Who can join", selection: $policy) {
                        Text("Anyone").tag("open")
                        Text("By request").tag("request")
                        Text("Invite only").tag("invite_only")
                    }
                }
                if let notice = model.notice {
                    Section { Text(verbatim: notice).foregroundStyle(Color(ColorTokens.stateDanger)) }
                }
            }
            .navigationTitle(Text("New clan"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await model.create(name: name, description: about, policy: policy, badge: badge) { onDone() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).count < 3 || model.busy)
                }
            }
        }
    }
}

/// Live preview + shape, colour and emblem. Pro emblems (D-074) show a PRO badge; free users get the paywall.
struct BadgeEditor: View {
    @Binding var style: ClanBadgeStyle
    let tag: String

    var body: some View {
        let r = style.resolved(tag: tag)
        VStack(spacing: SpacingTokens.m) {
            ClanEmblemView(style: style, tag: tag, size: 96)
                .frame(maxWidth: .infinity)
            Picker("Shape", selection: Binding(get: { r.shape }, set: { style.shape = $0 })) {
                Text("Shield").tag("shield")
                Text("Round").tag("round")
                Text("Hex").tag("hex")
            }
            .pickerStyle(.segmented)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SpacingTokens.xs), count: 8), spacing: SpacingTokens.xs) {
                ForEach(Cosmetics.badgeColors, id: \.self) { c in
                    Button { style.color = c } label: {
                        Circle().fill(Color(Cosmetics.badgeColor(c)))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white, lineWidth: r.color == c ? 3 : 0))
                            .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: c.capitalized))
                    .accessibilityAddTraits(r.color == c ? .isSelected : [])
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SpacingTokens.xs), count: 4), spacing: SpacingTokens.xs) {
                ForEach(Cosmetics.emblems) { e in
                    let locked = e.pro && !Monetization.isPro && r.emblem.id != e.id
                    Button {
                        if locked { Monetization.showPaywall("emblem") } else { style.emblem = e.id }
                    } label: {
                        Text(verbatim: e.glyph)
                            .font(.system(size: 30))
                            .opacity(locked ? 0.55 : 1)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m)
                                .strokeBorder(Color(r.emblem.id == e.id ? ColorTokens.brandFlame : ColorTokens.strokeSubtle),
                                              lineWidth: r.emblem.id == e.id ? 2 : 1))
                            .overlay(alignment: .topTrailing) { if e.pro { ProBadge().offset(x: 2, y: -4) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: e.id.capitalized))
                    .accessibilityHint(locked ? Text("Pushly Pro emblem") : Text(""))
                    .accessibilityAddTraits(r.emblem.id == e.id ? .isSelected : [])
                }
            }
            if !Monetization.isPro {
                Text("Emblems with the PRO badge come with Pushly Pro.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .padding(.vertical, SpacingTokens.s)
    }
}

struct ClanSettingsSheet: View {
    let model: ClanModel
    let onDone: () -> Void
    @State private var badge = ClanBadgeStyle()
    @State private var about = ""
    @State private var policy = "open"
    @State private var confirmLeave = false

    private var role: ClanRole { model.myRole ?? .member }

    var body: some View {
        NavigationStack {
            Form {
                if let home = model.home {
                    if role.canEditSettings {
                        Section { BadgeEditor(style: $badge, tag: home.summary.tag) } header: { SectionLabel("Badge") }
                        Section {
                            TextField("Description", text: $about, axis: .vertical).lineLimit(2...4)
                            Picker("Who can join", selection: $policy) {
                                Text("Anyone").tag("open")
                                Text("By request").tag("request")
                                Text("Invite only").tag("invite_only")
                            }
                        }
                    } else {
                        Section {
                            HStack(spacing: SpacingTokens.m) {
                                ClanEmblemView(style: home.summary.badge, tag: home.summary.tag, size: 56)
                                VStack(alignment: .leading) {
                                    Text(verbatim: home.summary.name).typography(TypographyTokens.titleM)
                                    if !home.summary.description.isEmpty {
                                        Text(verbatim: home.summary.description).typography(TypographyTokens.bodyS)
                                            .foregroundStyle(Color(ColorTokens.textSecondary))
                                    }
                                }
                            }
                            Text("Only the leader and co-leaders can change the badge and settings.")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                    }
                    if let notice = model.notice {
                        Section { Text(verbatim: notice).foregroundStyle(Color(ColorTokens.stateDanger)) }
                    }
                    Section {
                        Button(role == .leader && home.summary.memberCount == 1 ? "Disband clan" : "Leave clan", role: .destructive) {
                            confirmLeave = true
                        }
                        .frame(minHeight: TouchTarget.minimum)
                    }
                    .confirmationDialog("Leave \(home.summary.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
                        Button("Leave", role: .destructive) {
                            Task {
                                await model.leave()
                                onDone()
                            }
                        }
                    } message: {
                        Text("Your push-ups so far still count for this week's war.")
                    }
                }
            }
            .navigationTitle(Text("Clan settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDone) }
                if role.canEditSettings {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                if await model.update(badge: badge, description: about, policy: policy) { onDone() }
                            }
                        }
                        .disabled(model.busy)
                    }
                }
            }
            .onAppear {
                guard let s = model.home?.summary else { return }
                let r = (s.badge ?? ClanBadgeStyle()).resolved(tag: s.tag)
                badge = ClanBadgeStyle(shape: r.shape, color: r.color, emblem: r.emblem.id)
                about = s.description
                policy = s.joinPolicy
            }
        }
    }
}

// MARK: - Members

func roleTitle(_ r: ClanRole) -> String {
    switch r {
    case .leader: String(localized: "leader")
    case .coLeader: String(localized: "co-leader")
    case .elder: String(localized: "elder")
    case .member: String(localized: "member")
    }
}

struct ClanMembersSheet: View {
    let model: ClanModel
    let onDone: () -> Void

    private var role: ClanRole { model.myRole ?? .member }

    var body: some View {
        NavigationStack {
            List {
                if let home = model.home {
                    let ranked = home.members.sorted { ($0.warReps, $0.repsToday) > ($1.warReps, $1.repsToday) }
                    if ranked.count >= 3, ranked[0].warReps > 0 {
                        Section { Podium(top: Array(ranked.prefix(3))) }
                            .listRowBackground(Color.clear)
                    }
                    if role.canAcceptRequests, !home.requests.isEmpty {
                        Section {
                            ForEach(home.requests) { req in
                                HStack {
                                    AvatarView(username: req.user.username, presetID: req.user.avatarPreset, size: 36, frame: req.user.frame)
                                    VStack(alignment: .leading) {
                                        Text(verbatim: req.user.username).typography(TypographyTokens.titleS)
                                        if let message = req.message, !message.isEmpty {
                                            Text(verbatim: message).typography(TypographyTokens.caption)
                                        }
                                    }
                                    Spacer()
                                    Button("Accept") { Task { await model.respond(req.user.id, accept: true) } }
                                        .buttonStyle(.borderedProminent).tint(Color(ColorTokens.brandFlame))
                                    Button("Decline") { Task { await model.respond(req.user.id, accept: false) } }.buttonStyle(.bordered)
                                }
                                .frame(minHeight: TouchTarget.minimum)
                            }
                        } header: {
                            SectionLabel("Join requests")
                        }
                        .listRowBackground(Color(ColorTokens.bgSurface))
                    }
                    Section {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { i, m in
                            HStack(spacing: SpacingTokens.s) {
                                Text(verbatim: "\(i + 1)")
                                    .typography(TypographyTokens.titleS)
                                    .foregroundStyle(Color(i < 3 ? ColorTokens.leagueGold : ColorTokens.textTertiary))
                                    .frame(width: 26)
                                ProfileLink(.user(id: m.user.id)) { MemberRow(member: m) }
                                let menu = actions(for: m)
                                if !menu.isEmpty {
                                    Menu {
                                        memberActions(m)
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .foregroundStyle(Color(ColorTokens.textSecondary))
                                            .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                                    }
                                    .accessibilityLabel(Text("Actions for \(m.user.username)"))
                                }
                            }
                        }
                    } header: {
                        SectionLabel("Members \(home.summary.memberCount)/30")
                    } footer: {
                        Text("Sorted by push-ups for this week's war.").typography(TypographyTokens.caption)
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                }
            }
            .scrollContentBackground(.hidden)
            .arenaBackground(glow: ColorTokens.brandCyan, alignment: .top, offset: CGSize(width: 0, height: -260))
            .refreshable { await model.load() }
            .navigationTitle(Text("Members"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        }
    }

    private func actions(for m: ClanHome.Member) -> [String] {
        let other = ClanRole(rawValue: m.role) ?? .member
        var out = role.assignable(to: other).map(\.rawValue)
        if role == .leader, m.role != ClanRole.leader.rawValue { out.append("transfer") }
        if role.canKick(other) { out.append("kick") }
        return out
    }

    @ViewBuilder
    private func memberActions(_ m: ClanHome.Member) -> some View {
        let other = ClanRole(rawValue: m.role) ?? .member
        ForEach(role.assignable(to: other), id: \.self) { r in
            Button("Make \(roleTitle(r))") { Task { await model.setRole(m.user.id, r) } }
        }
        if role == .leader, other != .leader {
            Button("Make leader") { Task { await model.transfer(m.user.id) } }
        }
        if role.canKick(other) {
            Button("Remove from clan", role: .destructive) { Task { await model.kick(m.user.id) } }
        }
    }
}

/// This week's top three, on steps.
struct Podium: View {
    let top: [ClanHome.Member]

    var body: some View {
        HStack(alignment: .bottom, spacing: SpacingTokens.s) {
            if top.count > 1 { step(top[1], place: 2, height: 54, color: ColorTokens.leagueSilver) }
            step(top[0], place: 1, height: 76, color: ColorTokens.leagueGold)
            if top.count > 2 { step(top[2], place: 3, height: 40, color: ColorTokens.leagueBronze) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func step(_ m: ClanHome.Member, place: Int, height: CGFloat, color: TokenColor) -> some View {
        VStack(spacing: SpacingTokens.xs) {
            if place == 1 { Text(verbatim: "👑").font(.title2).accessibilityHidden(true) }
            AvatarView(username: m.user.username, presetID: m.user.avatarPreset, size: place == 1 ? 56 : 46, frame: m.user.frame)
            Text(verbatim: m.user.username).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textPrimary))
                .lineLimit(1)
            Text(verbatim: "\(m.warReps)").typography(TypographyTokens.titleS).foregroundStyle(Color(color))
            RoundedRectangle(cornerRadius: RadiusTokens.s)
                .fill(LinearGradient(colors: [Color(color).opacity(0.8), Color(color).opacity(0.25)], startPoint: .top, endPoint: .bottom))
                .frame(height: height)
                .overlay(Text(verbatim: "\(place)").typography(TypographyTokens.displayM).foregroundStyle(.white.opacity(0.9)))
        }
        .frame(maxWidth: .infinity)
    }
}

struct MemberRow: View {
    let member: ClanHome.Member

    var body: some View {
        HStack(spacing: SpacingTokens.m) {
            AvatarView(username: member.user.username, presetID: member.user.avatarPreset, size: 40, frame: member.user.frame)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpacingTokens.xs) {
                    Text(verbatim: member.user.username).typography(TypographyTokens.titleS)
                    if member.user.pro == true { ProBadge() }
                }
                Text(verbatim: roleTitle(ClanRole(rawValue: member.role) ?? .member).capitalized)
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(member.warReps) war").typography(TypographyTokens.bodyS)
                Text("\(member.repsToday) today")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .frame(minHeight: TouchTarget.minimum)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chat

/// Clan chat (doc 09 §5, D-076): bubbles like a messenger — mine on the right in the brand gradient, others on the left
/// with avatar and name, day separators, system lines as small pills, big emoji reactions. Refreshes every 5 s.
struct ClanChatView: View {
    let model: ClanModel
    @State private var text = ""
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: SpacingTokens.xs) {
                        if model.messages.isEmpty {
                            VStack(spacing: SpacingTokens.s) {
                                Text(verbatim: "👋").font(.system(size: 48)).accessibilityHidden(true)
                                Text("Say hi to your clan").typography(TypographyTokens.titleM)
                                    .foregroundStyle(Color(ColorTokens.textPrimary))
                                Text("Cheer each other on — every push-up counts in the Clan War.")
                                    .typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.textSecondary))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 80)
                        }
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { i, msg in
                            let prev = i > 0 ? model.messages[i - 1] : nil
                            if ChatLayout.newDay(msg, after: prev) {
                                DaySeparator(date: ChatLayout.date(msg.createdAt))
                            }
                            ChatRow(message: msg, mine: msg.user?.id == model.myUserId,
                                    firstInGroup: ChatLayout.startsGroup(msg, after: prev))
                                .id(msg.id)
                                .contextMenu {
                                    if msg.kind != "system", msg.user != nil, msg.user?.id != model.myUserId {
                                        ReportButton { reason in await Reporter.send(.message(msg.id), reason: reason) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, SpacingTokens.m)
                    .padding(.vertical, SpacingTokens.m)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.last?.id) { _, last in
                    if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
                .onAppear { if let last = model.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
            }
            if let notice = model.notice {
                Text(verbatim: notice)
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.stateDanger))
                    .padding(.horizontal, SpacingTokens.m)
            }
            composer
        }
        .navigationTitle(Text(verbatim: model.home?.summary.name ?? String(localized: "Clan chat")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                await model.loadMessages()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var composer: some View {
        VStack(spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.s) {
                ForEach(["👊", "🔥", "💪"], id: \.self) { e in
                    Button { Task { _ = await model.send(e, kind: "kudos") } } label: {
                        Text(verbatim: e)
                            .font(.title3)
                            .frame(width: TouchTarget.minimum, height: 36)
                            .background(Color(ColorTokens.bgElevated), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Send \(e)"))
                }
                Spacer()
            }
            HStack(alignment: .bottom, spacing: SpacingTokens.s) {
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($typing)
                    .typography(TypographyTokens.body)
                    .padding(.horizontal, SpacingTokens.m)
                    .padding(.vertical, 10)
                    .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
                let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    let body = text
                    Task { if await model.send(body) { text = "" } }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                        .background(empty ? AnyShapeStyle(Color(ColorTokens.strokeStrong)) : AnyShapeStyle(LinearGradient(GradientTokens.hero)),
                                    in: Circle())
                }
                .accessibilityLabel(Text("Send"))
                .disabled(empty)
            }
        }
        .padding(.horizontal, SpacingTokens.m)
        .padding(.top, SpacingTokens.s)
        .padding(.bottom, SpacingTokens.s)
        .background(Color(ColorTokens.bgSurface).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color(ColorTokens.strokeSubtle)).frame(height: 1) }
    }
}

/// Grouping rules for the chat (tested).
enum ChatLayout {
    static func date(_ iso: String) -> Date? {
        // Postgres may send microseconds; drop the fraction so one formatter covers every shape.
        let trimmed = iso.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: trimmed)
    }

    /// A day separator goes above the first message of every local day.
    static func newDay(_ msg: ClanMessage, after prev: ClanMessage?, calendar: Calendar = .current) -> Bool {
        guard let d = date(msg.createdAt) else { return false }
        guard let prev, let p = date(prev.createdAt) else { return true }
        return !calendar.isDate(d, inSameDayAs: p)
    }

    /// Name + avatar only on the first of consecutive messages by the same person within 5 minutes.
    static func startsGroup(_ msg: ClanMessage, after prev: ClanMessage?) -> Bool {
        guard let prev, prev.kind != "system", msg.kind != "system", prev.user?.id == msg.user?.id,
              let d = date(msg.createdAt), let p = date(prev.createdAt) else { return true }
        return d.timeIntervalSince(p) > 300
    }
}

struct DaySeparator: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(Self.label(date))
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .padding(.horizontal, SpacingTokens.sm)
                .padding(.vertical, 4)
                .background(Color(ColorTokens.bgElevated), in: Capsule())
                .padding(.vertical, SpacingTokens.s)
                .frame(maxWidth: .infinity)
        }
    }

    static func label(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct ChatRow: View {
    let message: ClanMessage
    let mine: Bool
    let firstInGroup: Bool

    private var time: String {
        ChatLayout.date(message.createdAt).map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
    }

    var body: some View {
        if message.kind == "system" {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: "shield.lefthalf.filled").font(.caption2).accessibilityHidden(true)
                Text(verbatim: message.body ?? "")
            }
            .typography(TypographyTokens.caption)
            .foregroundStyle(Color(ColorTokens.textTertiary))
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.04), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .bottom, spacing: SpacingTokens.s) {
                if mine {
                    Spacer(minLength: 56)
                } else {
                    if firstInGroup {
                        AvatarView(username: message.user?.username ?? "?", presetID: message.user?.avatarPreset, size: 30)
                    } else {
                        Color.clear.frame(width: 30, height: 1)
                    }
                }
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    if firstInGroup, !mine {
                        Text(verbatim: message.user?.username ?? String(localized: "Deleted user"))
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.brandCyan))
                            .padding(.leading, SpacingTokens.xs)
                    }
                    bubble
                    if firstInGroup || mine {
                        Text(verbatim: time)
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                            .padding(.horizontal, SpacingTokens.xs)
                    }
                }
                if !mine { Spacer(minLength: 56) }
            }
            .padding(.top, firstInGroup ? SpacingTokens.s : 0)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var bubble: some View {
        if message.kind == "kudos" {
            Text(verbatim: message.body ?? "").font(.system(size: 40))
        } else {
            Text(verbatim: message.body ?? "")
                .typography(TypographyTokens.body)
                .foregroundStyle(mine ? .white : Color(ColorTokens.textPrimary))
                .padding(.horizontal, SpacingTokens.m)
                .padding(.vertical, 9)
                .background(mine ? AnyShapeStyle(LinearGradient(GradientTokens.hero)) : AnyShapeStyle(Color(ColorTokens.bgElevated)),
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine ? 18 : 6,
                                                       bottomTrailingRadius: mine ? 6 : 18, topTrailingRadius: 18,
                                                       style: .continuous))
                .textSelection(.enabled)
        }
    }
}
