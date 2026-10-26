import DesignSystem
import SwiftUI

/// Profile → Friends (doc 15 §1, D-077): Activity (feed with kudos) · Friends (requests, friends, sent, blocked) ·
/// Add (username search, share link, QR code — the same ways as in Battle).
public struct FriendsView: View {
    @State private var model: FriendsModel
    @State private var tab: Int
    private let myUsername: String?

    /// `initialTab`: 0 Activity, 1 Friends, 2 Add.
    public init(model: FriendsModel, myUsername: String?, initialTab: Int = 0) {
        _model = State(initialValue: model)
        _tab = State(initialValue: initialTab)
        self.myUsername = myUsername
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: SpacingTokens.m) {
                    ScreenTitle("Friends", token: TypographyTokens.displayM)
                    Picker("Show", selection: $tab) {
                        Text("Activity").tag(0)
                        Text(model.list.incoming.isEmpty ? LocalizedStringKey("Friends") : LocalizedStringKey("Friends (\(model.list.incoming.count))")).tag(1)
                        Text("Add").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .listRowBackground(Color.clear)

            if let notice = model.notice {
                Section { InlineBanner(LocalizedStringKey(notice), kind: .info) }
                    .listRowBackground(Color.clear)
            }

            if tab == 0 {
                feedSection
            } else if tab == 1 {
                friendsSections
            } else {
                Section { AddFriendsPanel(model: model, myUsername: myUsername) }
                    .listRowBackground(Color(ColorTokens.bgSurface))
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
        .arenaBackground(glow: ColorTokens.brandCyan, alignment: .top, offset: CGSize(width: 0, height: -260))
        .toolbar {
            if let myUsername, let url = FriendLinks.profileURL(myUsername) {
                ShareLink(item: url, message: Text("Add me on Pushly")) {
                    Label("Share my link", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task { if !model.loaded { await model.load() } }
    }

    @ViewBuilder
    private var feedSection: some View {
        Section {
            if model.feed.isEmpty {
                Text(model.list.friends.isEmpty ? "Add friends to see their wake-ups and records here."
                                                : "Nothing from your friends in the last 7 days.")
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            ForEach(model.feed) { item in
                HStack(spacing: SpacingTokens.m) {
                    AvatarView(username: item.user.username, presetID: item.user.avatarPreset, size: 40, frame: item.user.frame)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.user.username).typography(TypographyTokens.titleS)
                        Text(verbatim: FriendsModel.describe(item))
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await model.kudos(item) }
                    } label: {
                        Text(verbatim: "👊 \(item.kudos)")
                            .typography(TypographyTokens.bodyS)
                            .padding(.horizontal, SpacingTokens.sm)
                            .frame(minHeight: TouchTarget.minimum)
                            .background(item.kudosByMe ? Color(ColorTokens.brandFlame).opacity(0.2) : Color(ColorTokens.bgElevated),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(item.kudosByMe)
                    .accessibilityLabel(Text(item.kudosByMe ? "Kudos given, \(item.kudos) total" : "Give kudos, \(item.kudos) so far"))
                }
            }
        } header: {
            SectionLabel("Last 7 days")
        }
        .listRowBackground(Color(ColorTokens.bgSurface))
    }

    @ViewBuilder
    private var friendsSections: some View {
        if !model.list.incoming.isEmpty {
            Section {
                ForEach(model.list.incoming) { user in
                    UserRow(user: user) {
                        HStack(spacing: SpacingTokens.s) {
                            Button("Accept") { Task { await model.respond(user, accept: true) } }
                                .buttonStyle(.borderedProminent).tint(Color(ColorTokens.brandFlame))
                            Button("Decline") { Task { await model.respond(user, accept: false) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                SectionLabel("Requests")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        }
        Section {
            if model.list.friends.isEmpty {
                VStack(alignment: .leading, spacing: SpacingTokens.s) {
                    Text("No friends yet — find them by username, share your link or show your QR code.")
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                    Button("Add friends") { tab = 2 }
                        .buttonStyle(.borderedProminent).tint(Color(ColorTokens.brandFlame))
                }
            }
            ForEach(model.list.friends) { user in
                NavigationLink {
                    UserProfileView(model: UserProfileModel(key: .id(user.id), service: model.service))
                } label: {
                    UserRow(user: user) {
                        if let streak = user.streak, streak > 0 { Pill("🔥 \(streak)") }
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { Task { await model.remove(user) } }
                    Button("Block") { Task { await model.block(user.id) } }.tint(Color(ColorTokens.stateWarning))
                }
            }
        } header: {
            SectionLabel("Friends \(model.list.friends.count)")
        }
        .listRowBackground(Color(ColorTokens.bgSurface))
        if !model.list.outgoing.isEmpty {
            Section {
                ForEach(model.list.outgoing) { user in
                    UserRow(user: user) {
                        Button("Cancel") { Task { await model.remove(user) } }.buttonStyle(.bordered)
                    }
                }
            } header: {
                SectionLabel("Sent")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        }
        if !model.list.blocked.isEmpty {
            Section {
                ForEach(model.list.blocked) { b in
                    HStack {
                        Text(verbatim: b.username)
                        Spacer()
                        Button("Unblock") { Task { await model.unblock(b.id) } }.buttonStyle(.bordered)
                    }
                    .frame(minHeight: TouchTarget.minimum)
                }
            } header: {
                SectionLabel("Blocked")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        }
    }
}

struct UserRow<Trailing: View>: View {
    let user: UserCard
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: SpacingTokens.m) {
            AvatarView(username: user.username, presetID: user.avatarPreset, size: 40, frame: user.frame)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpacingTokens.xs) {
                    Text(verbatim: user.username).typography(TypographyTokens.titleS)
                    if user.pro == true { ProBadge() }
                }
                Text("Level \(user.level)")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: TouchTarget.minimum)
    }
}
