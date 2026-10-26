import Core
import DesignSystem
import SwiftUI

/// The ways to add a friend (D-072 in Battle, D-077 in Profile, D-078): find by username, share my link, show my QR
/// code, scan a friend's QR code in the app (opens their profile with Add).
public struct AddFriendsPanel: View {
    @Bindable var model: FriendsModel
    let myUsername: String?
    @State private var showQR = false
    @State private var scanning = false
    @State private var scanned: ScannedUser?
    @State private var pendingScan: ScannedUser?
    @State private var badCode = false

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
            HStack(spacing: SpacingTokens.sm) {
                if let link {
                    ShareLink(item: link, message: Text("Add me on Pushly and let's battle!")) {
                        tile("Share link", "square.and.arrow.up", ColorTokens.brandCyan)
                    }
                    Button { showQR = true } label: { tile("My QR code", "qrcode", ColorTokens.brandVolt) }
                        .buttonStyle(.plain)
                }
                Button { scanning = true } label: { tile("Scan QR", "qrcode.viewfinder", ColorTokens.brandLime) }
                    .buttonStyle(.plain)
            }
            if badCode {
                InlineBanner("That QR code isn't a Pushly friend code.", kind: .warning)
            }
            Text("Next to each other? One of you shows the QR code, the other taps Scan QR — or uses the phone camera.")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
        }
        .sheet(isPresented: $showQR) {
            if let link, let myUsername { QRCodeSheet(url: link, username: myUsername) }
        }
        .sheet(isPresented: $scanning, onDismiss: {
            // open the profile once the scanner is gone (two sheets can't animate at once)
            if let pendingScan {
                scanned = pendingScan
                self.pendingScan = nil
            }
        }) {
            QRScannerSheet { text in
                if let name = ShareLinks.username(in: text) {
                    badCode = false
                    pendingScan = ScannedUser(username: name)
                } else {
                    badCode = true
                }
            }
        }
        .sheet(item: $scanned, onDismiss: { Task { await model.load() } }) { user in
            NavigationStack {
                UserProfileView(model: UserProfileModel(key: .username(user.username), service: model.service))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { scanned = nil } } }
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, _ icon: String, _ color: TokenColor) -> some View {
        VStack(spacing: SpacingTokens.xs) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color(color)).accessibilityHidden(true)
            Text(title).typography(TypographyTokens.button).foregroundStyle(Color(ColorTokens.textPrimary))
                .lineLimit(1).minimumScaleFactor(0.7)
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
    public static func profileURL(_ username: String) -> URL? { ShareLinks.profile(username) }
}

struct ScannedUser: Identifiable, Hashable {
    let username: String
    var id: String { username }
}

/// Profile tab card (D-077): friends at a glance — count, requests, faces, the newest activity — plus the three ways to
/// add someone. Opens the full Friends screen.
public struct ProfileFriendsCard: View {
    @State private var model: FriendsModel
    let myUsername: String?
    @State private var showQR = false
    @State private var scanning = false
    @State private var scanned: ScannedUser?
    @State private var pendingScan: ScannedUser?

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
            // friend requests right here — accept without digging (D-078)
            ForEach(model.list.incoming) { user in
                HStack(spacing: SpacingTokens.sm) {
                    AvatarView(username: user.username, presetID: user.avatarPreset, size: 36, frame: user.frame)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: user.username).typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.textPrimary)).lineLimit(1)
                        Text("wants to be friends").typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    }
                    Spacer(minLength: 0)
                    Button { Task { await model.respond(user, accept: false) } } label: {
                        Image(systemName: "xmark").font(.body.weight(.bold))
                            .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                            .background(Color(ColorTokens.bgElevated), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .accessibilityLabel(Text("Decline \(user.username)"))
                    Button { Task { await model.respond(user, accept: true) } } label: {
                        Text("Accept").typography(TypographyTokens.button).foregroundStyle(.white)
                            .padding(.horizontal, SpacingTokens.m)
                            .frame(minHeight: TouchTarget.minimum)
                            .background(Color(ColorTokens.brandFlame), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(SpacingTokens.s)
                .background(Color(ColorTokens.brandFlame).opacity(0.10), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
            }
            HStack(spacing: SpacingTokens.s) {
                NavigationLink {
                    FriendsView(model: model, myUsername: myUsername, initialTab: 2)
                } label: { action("Find", "magnifyingglass") }
                    .buttonStyle(.plain)
                if let myUsername, let link = FriendLinks.profileURL(myUsername) {
                    ShareLink(item: link, message: Text("Add me on Pushly and let's battle!")) { action("Share", "square.and.arrow.up") }
                    Button { showQR = true } label: { action("My QR", "qrcode") }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showQR) { QRCodeSheet(url: link, username: myUsername) }
                }
                Button { scanning = true } label: { action("Scan", "qrcode.viewfinder") }
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $scanning, onDismiss: {
            if let pendingScan {
                scanned = pendingScan
                self.pendingScan = nil
            }
        }) {
            QRScannerSheet { text in pendingScan = ShareLinks.username(in: text).map { ScannedUser(username: $0) } }
        }
        .sheet(item: $scanned, onDismiss: { Task { await model.load() } }) { user in
            NavigationStack {
                UserProfileView(model: UserProfileModel(key: .username(user.username), service: model.service))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { scanned = nil } } }
            }
        }
        .padding(SpacingTokens.ml)
        .background(
            LinearGradient(colors: [Color(ColorTokens.brandCyan).opacity(0.14), Color(ColorTokens.bgSurface)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .task {
            // new requests show up without leaving the tab (D-078); ask for push in context once
            PushPrompt.request(.friends)
            while !Task.isCancelled {
                await model.load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func action(_ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.body.weight(.semibold)).accessibilityHidden(true)
            Text(title).typography(TypographyTokens.caption).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color(ColorTokens.textPrimary))
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .accessibilityElement(children: .combine)
    }
}
