import DesignSystem
import SwiftUI

/// The ways to add a friend (D-072 in Battle, D-077 in Profile): find by username, share my link, show my QR code.
public struct AddFriendsPanel: View {
    @Bindable var model: FriendsModel
    let myUsername: String?
    @State private var showQR = false

    public init(model: FriendsModel, myUsername: String?) {
        self.model = model
        self.myUsername = myUsername
    }

    private var link: URL? { myUsername.flatMap { FriendLinks.profileURL($0) } }

    public var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack(spacing: SpacingTokens.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
                TextField(text: $model.query, prompt: Text("Find by username")) { Text("Find by username") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                        .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, SpacingTokens.m)
            .frame(minHeight: TouchTarget.minimum)
            .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
            .task(id: model.query) {
                try? await Task.sleep(for: .milliseconds(300))
                await model.search()
            }
            if model.query.trimmingCharacters(in: .whitespaces).count >= 2 {
                if model.results.isEmpty {
                    Text("Nobody found.").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                }
                ForEach(model.results) { user in
                    UserRow(user: user) { RelationButton(user: user, model: model) }
                }
            }
            if let link, let myUsername {
                HStack(spacing: SpacingTokens.sm) {
                    ShareLink(item: link, message: Text("Add me on Pushly and let's battle!")) {
                        tile("Share my link", "square.and.arrow.up", ColorTokens.brandCyan)
                    }
                    Button { showQR = true } label: { tile("My QR code", "qrcode", ColorTokens.brandVolt) }
                        .buttonStyle(.plain)
                }
                .sheet(isPresented: $showQR) { QRCodeSheet(url: link, username: myUsername) }
                Text("Next to each other? Show your QR code — your friend points their phone camera at it and taps Add.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, _ icon: String, _ color: TokenColor) -> some View {
        VStack(spacing: SpacingTokens.xs) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color(color)).accessibilityHidden(true)
            Text(title).typography(TypographyTokens.button).foregroundStyle(Color(ColorTokens.textPrimary))
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(Color(color).opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).strokeBorder(Color(color).opacity(0.35)))
    }
}

/// Add / Requested / Accept / Friends for a search result.
struct RelationButton: View {
    let user: UserCard
    let model: FriendsModel

    var body: some View {
        switch user.relation {
        case "friends": Pill("Friends", color: ColorTokens.stateSuccessText)
        case "outgoing": Pill("Requested")
        case "incoming":
            Button("Accept") { Task { await model.respond(user, accept: true) } }
                .buttonStyle(.borderedProminent).tint(Color(ColorTokens.brandFlame))
        default:
            Button { Task { await model.add(user) } } label: {
                Label("Add", systemImage: "person.badge.plus")
                    .typography(TypographyTokens.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SpacingTokens.m)
                    .frame(minHeight: TouchTarget.minimum)
                    .background(Color(ColorTokens.brandFlame), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

public enum FriendLinks {
    public static func profileURL(_ username: String) -> URL? { URL(string: "https://pushly.app/u/\(username)") }
}

/// Profile tab card (D-077): friends at a glance — count, requests, faces, the newest activity — plus the three ways to
/// add someone. Opens the full Friends screen.
public struct ProfileFriendsCard: View {
    @State private var model: FriendsModel
    let myUsername: String?
    @State private var showQR = false

    public init(model: FriendsModel, myUsername: String?) {
        _model = State(initialValue: model)
        self.myUsername = myUsername
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            NavigationLink {
                FriendsView(model: model, myUsername: myUsername, initialTab: 1)
            } label: {
                VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                    HStack {
                        Text("Friends").typography(TypographyTokens.titleM).foregroundStyle(Color(ColorTokens.textPrimary))
                        Text(verbatim: "\(model.list.friends.count)").typography(TypographyTokens.titleM)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                        if !model.list.incoming.isEmpty {
                            Text("\(model.list.incoming.count) new")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(ColorTokens.brandFlame), in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
                    }
                    if model.list.friends.isEmpty {
                        Text("Battle friends, cheer their wake-ups and race them up the ladder.")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                            .multilineTextAlignment(.leading)
                    } else {
                        HStack(spacing: -10) {
                            ForEach(model.list.friends.prefix(7)) { f in
                                AvatarView(username: f.username, presetID: f.avatarPreset, size: 40, frame: f.frame)
                                    .overlay(Circle().strokeBorder(Color(ColorTokens.bgSurface), lineWidth: 2))
                            }
                            if model.list.friends.count > 7 {
                                Text(verbatim: "+\(model.list.friends.count - 7)")
                                    .typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.textPrimary))
                                    .frame(width: 40, height: 40)
                                    .background(Color(ColorTokens.bgElevated), in: Circle())
                            }
                        }
                        .accessibilityHidden(true)
                        if let item = model.feed.first {
                            Text(verbatim: "\(item.user.username) \(FriendsModel.describe(item))")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textSecondary))
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: SpacingTokens.s) {
                NavigationLink {
                    FriendsView(model: model, myUsername: myUsername, initialTab: 2)
                } label: { action("Find", "magnifyingglass") }
                    .buttonStyle(.plain)
                if let myUsername, let link = FriendLinks.profileURL(myUsername) {
                    ShareLink(item: link, message: Text("Add me on Pushly and let's battle!")) { action("Share link", "square.and.arrow.up") }
                    Button { showQR = true } label: { action("QR code", "qrcode") }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showQR) { QRCodeSheet(url: link, username: myUsername) }
                }
            }
        }
        .padding(SpacingTokens.ml)
        .background(
            LinearGradient(colors: [Color(ColorTokens.brandCyan).opacity(0.14), Color(ColorTokens.bgSurface)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .task { if !model.loaded { await model.load() } }
    }

    private func action(_ title: LocalizedStringKey, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .typography(TypographyTokens.button)
            .foregroundStyle(Color(ColorTokens.textPrimary))
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
    }
}
