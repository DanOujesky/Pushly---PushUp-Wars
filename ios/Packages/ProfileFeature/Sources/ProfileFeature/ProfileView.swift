import Core
import DesignSystem
import Networking
import SwiftUI

public struct ProfileView: View {
    @State private var model: ProfileViewModel
    @State private var confirmSignOut = false
    private let appVersion: String
    /// Stats card (StatsFeature `ProfileStatsCard`, opens the full Stats screen). Nil = guest / no backend.
    private let stats: AnyView?
    /// Friends card (SocialFeature `ProfileFriendsCard`). Nil = none.
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
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    HStack {
                        ScreenTitle("Profile", token: TypographyTokens.displayM)
                        Spacer()
                        NavigationLink { settings } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                                .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                                .background(Color(ColorTokens.bgSurface), in: Circle())
                        }
                        .accessibilityLabel(Text("Settings"))
                    }
                    hero
                    if model.isGuest {
                        Card {
                            VStack(alignment: .leading, spacing: SpacingTokens.m) {
                                Text("You're using Pushly as a guest. Your alarm works, but battles, leaderboards and clans need an account.")
                                    .typography(TypographyTokens.bodyS)
                                    .foregroundStyle(Color(ColorTokens.textSecondary))
                                PrimaryButton("Create an account") { model.createAccount() }
                            }
                        }
                    } else {
                        if let stats {
                            SectionLabel("Your stats")
                            stats
                        }
                        if let friends {
                            SectionLabel("Friends")
                            friends
                        }
                        if let pro {
                            SectionLabel("Pushly Pro")
                            Card { pro }
                        }
                    }
                    if let failure = model.failure {
                        InlineBanner(failure == .network
                            ? "No connection — your change wasn't saved."
                            : "Your change wasn't saved. Please try again.")
                    }
                }
                .padding(.horizontal, SpacingTokens.l)
                .padding(.bottom, SpacingTokens.xl)
            }
            .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -260))
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { await model.refresh() }
        }
    }

    /// Hero (D-077): framed avatar with the level on it, name, PRO, trophies.
    private var hero: some View {
        HStack(spacing: SpacingTokens.m) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(username: model.profile?.username ?? "Guest", presetID: model.profile?.avatarPreset, size: 96,
                           frame: ProState.shared.myFrame)
                if let profile = model.profile {
                    Text(verbatim: "\(profile.level)")
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.bgBase))
                        .frame(minWidth: 30, minHeight: 30)
                        .background(Color(ColorTokens.brandVolt), in: Circle())
                        .overlay(Circle().strokeBorder(Color(ColorTokens.bgBase), lineWidth: 3))
                        .accessibilityLabel(Text("Level \(profile.level)"))
                }
            }
            VStack(alignment: .leading, spacing: SpacingTokens.s) {
                HStack(spacing: SpacingTokens.s) {
                    Text(model.profile?.username ?? String(localized: "Guest"))
                        .typography(TypographyTokens.name)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if model.profile?.isPro == true || ProState.shared.isPro { ProBadge() }
                }
                if let profile = model.profile {
                    HStack(spacing: SpacingTokens.s) {
                        Pill("🏆 \(profile.trophies)", color: ColorTokens.leagueGold)
                        Pill("Level \(profile.level)", color: ColorTokens.brandVoltText)
                    }
                } else {
                    Pill("Alarm only", color: ColorTokens.brandFlameText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SpacingTokens.ml)
        .background(
            LinearGradient(colors: [Color(ColorTokens.brandVolt).opacity(0.16), Color(ColorTokens.bgSurface)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.xl, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.xl, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .accessibilityElement(children: .combine)
    }

    /// Settings (D-077): privacy, account & data, help and legal, sign out — off the main page.
    private var settings: some View {
        List {
            if let profile = model.profile {
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
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
        .navigationTitle(Text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .confirmationDialog("Sign out of Pushly?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
        } message: {
            Text("Your alarms stay on this phone.")
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
