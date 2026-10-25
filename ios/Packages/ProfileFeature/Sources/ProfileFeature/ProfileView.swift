import Core
import DesignSystem
import Networking
import SwiftUI

public struct ProfileView: View {
    @State private var model: ProfileViewModel
    @State private var confirmSignOut = false
    private let appVersion: String
    /// Stats & achievements screen (StatsFeature), pushed from the Progress row. Nil = no row (guest / no backend).
    private let stats: AnyView?
    /// Friends & activity (SocialFeature). Nil = no row.
    private let friends: AnyView?
    /// Account & data (notifications, export, deletion). Nil = no row.
    private let account: AnyView?

    /// Pushly Pro row + ad privacy (ShopFeature, D-073).
    private let pro: AnyView?

    public init(model: ProfileViewModel, appVersion: String, stats: AnyView? = nil, friends: AnyView? = nil,
                account: AnyView? = nil, pro: AnyView? = nil) {
        self.pro = pro
        _model = State(initialValue: model)
        self.appVersion = appVersion
        self.stats = stats
        self.friends = friends
        self.account = account
    }

    public var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                if model.isGuest {
                    Section {
                        Text("You're using Pushly as a guest. Your alarm works, but battles, leaderboards and clans need an account.")
                            .font(.token(TypographyTokens.bodyS))
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                        PrimaryButton("Create an account") { model.createAccount() }
                            .padding(.vertical, SpacingTokens.xs)
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                } else if let profile = model.profile {
                    if let pro {
                        Section { pro }
                            .listRowBackground(Color(ColorTokens.bgSurface))
                    }
                    if stats != nil || friends != nil {
                        Section {
                            if let stats {
                                NavigationLink {
                                    stats
                                } label: {
                                    Label("Stats & achievements", systemImage: "chart.bar.xaxis")
                                        .frame(minHeight: TouchTarget.minimum)
                                }
                            }
                            if let friends {
                                NavigationLink {
                                    friends
                                } label: {
                                    Label("Friends & activity", systemImage: "person.2.fill")
                                        .frame(minHeight: TouchTarget.minimum)
                                }
                            }
                        } header: {
                            SectionLabel("Progress")
                        }
                        .listRowBackground(Color(ColorTokens.bgSurface))
                    }
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
                        .tint(Color(ColorTokens.brandFlame))
                    } header: {
                        SectionLabel("Privacy")
                    } footer: {
                        Text("If you hide yourself, your scores still count but your name shows as \"Anonymous athlete\".")
                            .typography(TypographyTokens.caption)
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))

                    if let failure = model.failure {
                        Section {
                            InlineBanner(failure == .network
                                ? "No connection — your change wasn't saved."
                                : "Your change wasn't saved. Please try again.")
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    Section {
                        if let account {
                            NavigationLink {
                                account
                            } label: {
                                Label("Account & data", systemImage: "person.badge.key.fill")
                                    .frame(minHeight: TouchTarget.minimum)
                            }
                        }
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    }
                    .listRowBackground(Color(ColorTokens.bgSurface))
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    legalLink("Help & support", systemImage: "questionmark.circle", url: LegalLinks.support)
                    legalLink("Terms of Use", systemImage: "doc.text", url: LegalLinks.terms)
                    legalLink("Privacy Policy", systemImage: "hand.raised", url: LegalLinks.privacy)
                    legalLink("Community Guidelines", systemImage: "person.3", url: LegalLinks.community)
                } header: {
                    SectionLabel("About")
                }
                .listRowBackground(Color(ColorTokens.bgSurface))
            }
            .scrollContentBackground(.hidden)
            .typography(TypographyTokens.body)
            .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -260))
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { await model.refresh() }
            .confirmationDialog("Sign out of Pushly?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            } message: {
                Text("Your alarms stay on this phone.")
            }
        }
    }

    private func legalLink(_ title: LocalizedStringKey, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Color(ColorTokens.textPrimary))
        .accessibilityHint(Text("Opens in the browser"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            ScreenTitle("Profile", token: TypographyTokens.displayM)
            HStack(spacing: SpacingTokens.m) {
                AvatarView(username: model.profile?.username ?? "Guest", presetID: model.profile?.avatarPreset, size: 80,
                           frame: ProState.shared.myFrame)
                VStack(alignment: .leading, spacing: SpacingTokens.s) {
                    Text(model.profile?.username ?? String(localized: "Guest"))
                        .typography(TypographyTokens.name)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let profile = model.profile {
                        HStack(spacing: SpacingTokens.s) {
                            Pill("Level \(profile.level)", color: ColorTokens.brandVoltText)
                            Pill("\(profile.trophies) trophies", color: ColorTokens.leagueGold)
                        }
                    } else {
                        Pill("Alarm only", color: ColorTokens.brandFlameText)
                    }
                }
            }
        }
        .padding(.top, SpacingTokens.l)
        .padding(.bottom, SpacingTokens.s)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Signed in") {
    ProfileView(model: ProfileViewModel(
        profile: Profile(id: UUID(), username: "AnaFit", onboardingCompleted: true, avatarPreset: "preset.volt", trophies: 640, level: 7),
        profiles: InMemoryBackend(), auth: InMemoryBackend(), onSignedOut: {}, onCreateAccount: {}
    ), appVersion: "0.1.0 (1)")
    .preferredColorScheme(.dark)
}

#Preview("Guest") {
    ProfileView(model: ProfileViewModel(profile: nil, profiles: nil, auth: nil, onSignedOut: {}, onCreateAccount: {}),
                appVersion: "0.1.0 (1)")
}
