import DesignSystem
import Networking
import SwiftUI

public struct ProfileView: View {
    @State private var model: ProfileViewModel
    @State private var confirmSignOut = false
    private let appVersion: String

    public init(model: ProfileViewModel, appVersion: String) {
        _model = State(initialValue: model)
        self.appVersion = appVersion
    }

    public var body: some View {
        NavigationStack {
            List {
                Section { header }

                if model.isGuest {
                    Section {
                        Text("You're using Pushly as a guest. Your alarm works, but battles, leaderboards and clans need an account.")
                            .font(.token(TypographyTokens.bodyS))
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                        Button("Create an account") { model.createAccount() }
                            .frame(minHeight: TouchTarget.minimum)
                    }
                } else if let profile = model.profile {
                    Section {
                        Picker("Profile visible to", selection: Binding(
                            get: { profile.profileVisibility },
                            set: { newValue in Task { await model.setVisibility(newValue) } }
                        )) {
                            Text("Everyone").tag(ProfileVisibility.public)
                            Text("Friends").tag(ProfileVisibility.friends)
                            Text("Only me").tag(ProfileVisibility.private)
                        }
                        Toggle("Show me on leaderboards", isOn: Binding(
                            get: { profile.leaderboardVisible },
                            set: { newValue in Task { await model.setLeaderboardVisible(newValue) } }
                        ))
                    } header: {
                        Text("Privacy")
                    } footer: {
                        Text("If you hide yourself, your scores still count but your name shows as \"Anonymous athlete\".")
                    }

                    if let failure = model.failure {
                        Section {
                            InlineBanner(failure == .network
                                ? "No connection — your change wasn't saved."
                                : "Your change wasn't saved. Please try again.")
                        }
                    }

                    Section {
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Profile")
            .refreshable { await model.refresh() }
            .confirmationDialog("Sign out of Pushly?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            } message: {
                Text("Your alarms stay on this phone.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: SpacingTokens.m) {
            AvatarView(username: model.profile?.username ?? "Guest", presetID: model.profile?.avatarPreset, size: 64)
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(model.profile?.username ?? String(localized: "Guest"))
                    .font(.token(TypographyTokens.titleM))
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                if let profile = model.profile {
                    Text("Level \(profile.level) · \(profile.trophies) trophies")
                        .font(.token(TypographyTokens.bodyS))
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                }
            }
        }
        .padding(.vertical, SpacingTokens.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Signed in") {
    ProfileView(model: ProfileViewModel(
        profile: Profile(id: UUID(), username: "AnaFit", onboardingCompleted: true, avatarPreset: "preset.volt", trophies: 640, level: 7),
        profiles: InMemoryBackend(), auth: InMemoryBackend(), onSignedOut: {}, onCreateAccount: {}
    ), appVersion: "0.1.0 (1)")
}

#Preview("Guest") {
    ProfileView(model: ProfileViewModel(profile: nil, profiles: nil, auth: nil, onSignedOut: {}, onCreateAccount: {}),
                appVersion: "0.1.0 (1)")
}
