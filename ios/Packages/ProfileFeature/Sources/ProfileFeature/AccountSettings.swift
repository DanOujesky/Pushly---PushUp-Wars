import Core
import DesignSystem
import Foundation
import Networking
import Observation
import SwiftUI

/// Account & data (doc 16 §4, doc 15 §2): notification categories, quiet hours, data export, account deletion.
@MainActor
@Observable
public final class AccountModel {
    public struct Prefs: Codable, Equatable, Sendable {
        public var categories: [String: Bool] = [:]
        public var quietStart = "22:00"
        public var quietEnd = "07:00"
    }

    public static let categories = ["social", "battles", "clan", "activity", "promotions"]

    public private(set) var prefs = Prefs()
    /// Other players may race an anonymous recording of this user's battles (doc 07 §7). Off = runs deleted.
    public private(set) var ghostContribution = true
    public private(set) var exportURL: URL?
    public private(set) var working = false
    public private(set) var message: String?
    /// The server wants a fresh sign-in before deleting (JWT older than 15 minutes).
    public private(set) var needsReauth = false

    private let account: any AccountServicing
    private let onDeleted: @MainActor () -> Void

    public init(account: any AccountServicing, onDeleted: @escaping @MainActor () -> Void) {
        self.account = account
        self.onDeleted = onDeleted
    }

    public func enabled(_ category: String) -> Bool { prefs.categories[category] ?? (category != "promotions") }

    public func load() async {
        if let data = try? await account.notificationPrefs(),
           let p = try? JSONDecoder().decode(Prefs.self, from: data) {
            prefs = p
        }
        if let data = try? await account.privacySettings(),
           let settings = try? JSONDecoder().decode(PrivacySettings.self, from: data) {
            ghostContribution = !settings.ghostOptOut
        }
    }

    private struct PrivacySettings: Decodable { let ghostOptOut: Bool }

    public func setGhostContribution(_ on: Bool) async {
        let before = ghostContribution
        ghostContribution = on
        do {
            try await account.setGhostOptOut(!on)
            message = nil
        } catch {
            ghostContribution = before
            message = String(localized: "Your change wasn't saved. Please try again.")
        }
    }

    public func set(_ category: String, _ on: Bool) async {
        prefs.categories[category] = on
        await save()
    }

    public func setQuiet(start: String, end: String) async {
        prefs.quietStart = start
        prefs.quietEnd = end
        await save()
    }

    private func save() async {
        do {
            let body = try JSONEncoder().encode(prefs)
            if let p = try? JSONDecoder().decode(Prefs.self, from: try await account.setNotificationPrefs(body)) { prefs = p }
            message = nil
        } catch {
            message = String(localized: "Your change wasn't saved. Please try again.")
        }
    }

    /// Writes the export to a temporary JSON file for the share sheet.
    public func export() async {
        working = true
        defer { working = false }
        do {
            let data = try await account.exportMyData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pushly-my-data.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            message = nil
        } catch {
            message = String(localized: "The export failed. Please try again.")
        }
    }

    public func delete() async {
        working = true
        defer { working = false }
        do {
            try await account.deleteMyAccount()
            onDeleted()
        } catch {
            let text = String(describing: error)
            needsReauth = text.contains("reauth") || text.contains("sign in again")
            message = needsReauth ? String(localized: "For your safety, sign in again and then delete the account.")
                                  : String(localized: "The account couldn't be deleted. Please try again.")
        }
    }
}

public struct AccountSettingsView: View {
    @State private var model: AccountModel
    @State private var confirmDelete = false
    @Environment(\.openURL) private var openURL
    private let onSignInAgain: () -> Void

    public init(model: AccountModel, onSignInAgain: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onSignInAgain = onSignInAgain
    }

    private func title(_ c: String) -> LocalizedStringKey {
        switch c {
        case "social": "Friends & kudos"
        case "battles": "Battle invites"
        case "clan": "Clan"
        case "activity": "Results & achievements"
        default: "News & offers"
        }
    }

    public var body: some View {
        List {
            Section {
                ForEach(AccountModel.categories, id: \.self) { c in
                    Toggle(title(c), isOn: Binding(get: { model.enabled(c) }, set: { on in Task { await model.set(c, on) } }))
                        .tint(Color(ColorTokens.brandFlame))
                }
            } header: {
                SectionLabel("Notifications")
            } footer: {
                Text("Quiet hours \(model.prefs.quietStart)–\(model.prefs.quietEnd): only alarm-related notifications come through.")
                    .typography(TypographyTokens.caption)
            }
            .listRowBackground(Color(ColorTokens.bgSurface))

            Section {
                Button {
                    Task { await model.export() }
                } label: {
                    Label("Download my data", systemImage: "arrow.down.doc").frame(minHeight: TouchTarget.minimum)
                }
                .disabled(model.working)
                if let url = model.exportURL {
                    ShareLink(item: url) { Label("Share the export file", systemImage: "square.and.arrow.up") }
                }
                if let manage = URL(string: "https://apps.apple.com/account/subscriptions") {
                    Button {
                        openURL(manage)
                    } label: {
                        Label("Manage subscription", systemImage: "creditcard").frame(minHeight: TouchTarget.minimum)
                    }
                }
            } header: {
                SectionLabel("Your data")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))

            Section {
                Button("Delete account", role: .destructive) { confirmDelete = true }
                    .disabled(model.working)
                if model.needsReauth {
                    Button("Sign in again") { onSignInAgain() }
                }
            } footer: {
                Text("Deleting removes your profile, stats, friends and clan membership for good. It doesn't cancel an App Store subscription — use Manage subscription for that.")
                    .typography(TypographyTokens.caption)
            }
            .listRowBackground(Color(ColorTokens.bgSurface))

            if let message = model.message {
                Section { InlineBanner(LocalizedStringKey(message), kind: .warning) }.listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(Text("Account & data"))
        .toolbarVisibility(.visible, for: .navigationBar)
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -260))
        .confirmationDialog("Delete your Pushly account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete for good", role: .destructive) { Task { await model.delete() } }
        } message: {
            Text("This can't be undone. Your alarms stay on this phone.")
        }
        .task { await model.load() }
    }
}
