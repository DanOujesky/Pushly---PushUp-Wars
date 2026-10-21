import DesignSystem
import SwiftUI

/// Clan tab (doc 09 §4): clan home when in a clan, otherwise discovery + create.
public struct ClanTabView: View {
    @State private var model: ClanModel

    public init(model: ClanModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !model.loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let home = model.home {
                    ClanHomeView(model: model, home: home)
                } else {
                    ClanDiscoveryView(model: model)
                }
            }
            .arenaBackground(glow: ColorTokens.brandCyan, alignment: .top, offset: CGSize(width: 0, height: -260))
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .task { await model.load() }
    }
}

struct ClanBadge: View {
    let tag: String
    var size: CGFloat = 56

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [Color(ColorTokens.brandCyan), Color(ColorTokens.brandVolt)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(verbatim: tag)
                    .font(.system(size: size * 0.26, weight: .black))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .padding(4)
            }
            .accessibilityHidden(true)
    }
}

struct ClanDiscoveryView: View {
    @Bindable var model: ClanModel
    @State private var creating = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: SpacingTokens.m) {
                    ScreenTitle("Clans", token: TypographyTokens.displayM)
                    Text("Team up with up to 30 people and win the weekly Clan War together.")
                        .typography(TypographyTokens.body)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                    PrimaryButton("Create a clan") { creating = true }
                }
            }
            .listRowBackground(Color.clear)
            if let notice = model.notice {
                Section { InlineBanner(LocalizedStringKey(notice), kind: .info) }.listRowBackground(Color.clear)
            }
            Section {
                if model.results.isEmpty {
                    Text("No clans found.").foregroundStyle(Color(ColorTokens.textTertiary))
                }
                ForEach(model.results) { clan in
                    HStack(spacing: SpacingTokens.m) {
                        ClanBadge(tag: clan.tag, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(clan.name) [\(clan.tag)]").typography(TypographyTokens.titleS)
                            Text("\(clan.memberCount)/\(clan.maxMembers) members · rating \(clan.rating)")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 0)
                        if clan.requested {
                            Pill("Requested")
                        } else if clan.joinPolicy != "invite_only", clan.memberCount < clan.maxMembers {
                            Button(clan.joinPolicy == "open" ? "Join" : "Ask") { Task { await model.join(clan) } }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(ColorTokens.brandFlame))
                                .disabled(model.busy)
                        }
                    }
                    .frame(minHeight: TouchTarget.minimum)
                }
            } header: {
                SectionLabel(model.query.isEmpty ? "Recommended" : "Results")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $model.query, prompt: Text("Clan name or tag"))
        .onChange(of: model.query) { Task { await model.search() } }
        .refreshable { await model.search() }
        .sheet(isPresented: $creating) { CreateClanView(model: model) { creating = false } }
    }
}

struct CreateClanView: View {
    let model: ClanModel
    let onDone: () -> Void
    @State private var name = ""
    @State private var tag = ""
    @State private var about = ""
    @State private var policy = "open"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (3–24)", text: $name)
                    TextField("Tag (3–5 letters or digits)", text: $tag)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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
                            if await model.create(name: name, tag: tag, description: about, policy: policy) { onDone() }
                        }
                    }
                    .disabled(name.count < 3 || tag.count < 3 || model.busy)
                }
            }
        }
    }
}

struct ClanHomeView: View {
    let model: ClanModel
    let home: ClanHome
    @State private var confirmLeave = false

    private var role: ClanRole { model.myRole ?? .member }

    var body: some View {
        List {
            Section {
                HStack(spacing: SpacingTokens.m) {
                    ClanBadge(tag: home.summary.tag)
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        Text(verbatim: home.summary.name).typography(TypographyTokens.name)
                        Text("[\(home.summary.tag)] · \(home.summary.memberCount)/30 · rating \(home.summary.rating)")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                }
                .accessibilityElement(children: .combine)
                if !home.summary.description.isEmpty {
                    Text(verbatim: home.summary.description).foregroundStyle(Color(ColorTokens.textSecondary))
                }
                NavigationLink {
                    ClanChatView(model: model)
                } label: {
                    Label("Clan chat", systemImage: "bubble.left.and.bubble.right.fill").frame(minHeight: TouchTarget.minimum)
                }
            }
            .listRowBackground(Color(ColorTokens.bgSurface))

            if let notice = model.notice {
                Section { InlineBanner(LocalizedStringKey(notice), kind: .info) }.listRowBackground(Color.clear)
            }

            Section {
                if let war = home.war {
                    WarCard(war: war, us: home.summary)
                } else {
                    Text(home.summary.memberCount < 5 ? "Clan Wars start every Monday for clans with at least 5 members."
                                                      : "Your first Clan War starts next Monday.")
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                }
            } header: {
                SectionLabel("Clan War")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))

            if role.canAcceptRequests, !home.requests.isEmpty {
                Section {
                    ForEach(home.requests) { req in
                        HStack {
                            AvatarView(username: req.user.username, presetID: req.user.avatarPreset, size: 36)
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
                ForEach(home.members.sorted { $0.warReps > $1.warReps }) { m in
                    MemberRow(member: m)
                        .contextMenu { memberActions(m) }
                }
            } header: {
                SectionLabel("Members")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))

            Section {
                Button(role == .leader && home.summary.memberCount == 1 ? "Disband clan" : "Leave clan", role: .destructive) {
                    confirmLeave = true
                }
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        }
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
        .confirmationDialog("Leave \(home.summary.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await model.leave() } }
        } message: {
            Text("Your push-ups so far still count for this week's war.")
        }
    }

    @ViewBuilder
    private func memberActions(_ m: ClanHome.Member) -> some View {
        let other = ClanRole(rawValue: m.role) ?? .member
        ForEach(role.assignable(to: other), id: \.self) { r in
            Button("Make \(roleTitle(r))") { Task { await model.setRole(m.user.id, r) } }
        }
        if role == .leader {
            Button("Make leader") { Task { await model.transfer(m.user.id) } }
        }
        if role.canKick(other) {
            Button("Remove from clan", role: .destructive) { Task { await model.kick(m.user.id) } }
        }
    }
}

func roleTitle(_ r: ClanRole) -> String {
    switch r {
    case .leader: String(localized: "leader")
    case .coLeader: String(localized: "co-leader")
    case .elder: String(localized: "elder")
    case .member: String(localized: "member")
    }
}

struct MemberRow: View {
    let member: ClanHome.Member

    var body: some View {
        HStack(spacing: SpacingTokens.m) {
            AvatarView(username: member.user.username, presetID: member.user.avatarPreset, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: member.user.username).typography(TypographyTokens.titleS)
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

struct WarCard: View {
    let war: ClanWar
    let us: ClanSummary

    var body: some View {
        let total = max(war.score.us + war.score.them, 1)
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack {
                Text(verbatim: "[\(us.tag)] \(war.score.us)").typography(TypographyTokens.titleM)
                    .foregroundStyle(Color(ColorTokens.brandFlameText))
                Spacer()
                Text(verbatim: war.opponent.map { "\(war.score.them) [\($0.tag)]" } ?? String(localized: "Bye week"))
                    .typography(TypographyTokens.titleM)
                    .foregroundStyle(Color(ColorTokens.brandVoltText))
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(Color(ColorTokens.brandFlame))
                        .frame(width: max(4, geo.size.width * CGFloat(war.score.us) / CGFloat(total)))
                    Capsule().fill(Color(ColorTokens.brandVolt))
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            Text(war.status == "finished" ? "War over"
                                          : "Today you: +\(war.myToday.counted) (full until \(war.myToday.fullCap), half until \(war.myToday.halfCap))")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Clan chat (doc 09 §5): newest at the bottom, refreshes every 5 s while open, quick reactions.
struct ClanChatView: View {
    let model: ClanModel
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SpacingTokens.sm) {
                        ForEach(model.messages) { msg in
                            MessageRow(message: msg).id(msg.id)
                        }
                    }
                    .padding(SpacingTokens.l)
                }
                .onChange(of: model.messages.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            if let notice = model.notice {
                Text(verbatim: notice).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.stateDanger))
            }
            HStack(spacing: SpacingTokens.s) {
                ForEach(["👊", "🔥", "💪"], id: \.self) { e in
                    Button { Task { _ = await model.send(e, kind: "kudos") } } label: {
                        Text(verbatim: e).frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                    }
                    .accessibilityLabel(Text("Send \(e)"))
                }
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let body = text
                    Task { if await model.send(body) { text = "" } }
                } label: {
                    Image(systemName: "paperplane.fill").frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                }
                .accessibilityLabel(Text("Send"))
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, SpacingTokens.m)
            .padding(.vertical, SpacingTokens.s)
            .background(Color(ColorTokens.bgSurface))
        }
        .navigationTitle(Text("Clan chat"))
        .toolbarVisibility(.visible, for: .navigationBar)
        .arenaBackground(glow: ColorTokens.brandCyan, alignment: .top, offset: CGSize(width: 0, height: -260))
        .task {
            while !Task.isCancelled {
                await model.loadMessages()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

struct MessageRow: View {
    let message: ClanMessage

    var body: some View {
        if message.kind == "system" {
            Text(verbatim: message.body ?? "")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
                .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: SpacingTokens.s) {
                AvatarView(username: message.user?.username ?? "?", presetID: message.user?.avatarPreset, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: message.user?.username ?? String(localized: "Deleted user"))
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                    Text(verbatim: message.body ?? "")
                        .typography(message.kind == "kudos" ? TypographyTokens.titleL : TypographyTokens.body)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
