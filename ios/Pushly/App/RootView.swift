import DesignSystem
import Networking
import OnboardingFeature
import ProfileFeature
import SwiftUI

/// Switches between launch, onboarding and the main tabs based on `AppSession.state`.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .launching:
                LaunchView()
            case .updateRequired:
                ForceUpdateView()
            case .welcome:
                WelcomeView { session.welcomeFinished() }
            case .signIn:
                NavigationStack {
                    SignInView(
                        model: SignInViewModel(auth: session.auth) { _ in Task { await session.signedIn() } },
                        linkFailed: session.linkSignInFailed,
                        onGuest: { session.continueAsGuest() }
                    )
                }
            case let .profileSetup(profile):
                if let profiles = session.profiles {
                    NavigationStack {
                        ProfileSetupView(model: ProfileSetupViewModel(profile: profile, profiles: profiles) { completed in
                            session.profileCompleted(completed)
                        })
                    }
                }
            case let .main(profile):
                MainTabsView(profile: profile)
            }
        }
        .animation(.easeInOut(duration: MotionTokens.baseSeconds), value: session.state)
        // Arena look is dark-only for now (D-033).
        .preferredColorScheme(.dark)
        .task { await session.start() }
    }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: SpacingTokens.xl - 4) {
            LogoMark(size: 112)
            VStack(spacing: SpacingTokens.s) {
                Wordmark(token: TypographyTokens.displayLogo)
                Text(verbatim: "PushUp Wars")
                    .typography(TypographyTokens.labelLogo)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            ProgressView()
                .tint(Color(ColorTokens.textTertiary))
                .padding(.bottom, SpacingTokens.xxxl)
        }
        .arenaBackground(alignment: .center, offset: CGSize(width: 0, height: 40))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Pushly is loading"))
    }
}

/// Shown when remote config says this version is no longer supported (doc 03 §7).
struct ForceUpdateView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: SpacingTokens.l) {
            Spacer()
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(ColorTokens.bgSurface))
                .stroke(Color(ColorTokens.strokeStrong), lineWidth: 1)
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Color(ColorTokens.brandVoltText))
                }
                .accessibilityHidden(true)
            VStack(spacing: SpacingTokens.sm) {
                ScreenTitle("New version\nready")
                    .multilineTextAlignment(.center)
                Text("Update Pushly to keep your alarms, streak and trophies working. It takes a few seconds.")
                    .typography(TypographyTokens.body)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            Label("Your progress is saved", systemImage: "checkmark")
                .typography(TypographyTokens.bodyS)
                .fontWeight(.semibold)
                .foregroundStyle(Color(ColorTokens.stateSuccessText))
                .padding(.horizontal, SpacingTokens.m)
                .padding(.vertical, SpacingTokens.sm)
                .background(Color(ColorTokens.stateSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: RadiusTokens.s))
            Spacer()
            PrimaryButton("Update now") {
                if let url = StoreLinks.appStore { openURL(url) }
            }
        }
        .padding(.horizontal, SpacingTokens.l)
        .padding(.bottom, SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .center, offset: CGSize(width: 0, height: -60))
    }
}

/// Store pages for the update prompt. The App Store id is only known after the first App Store Connect release
/// (open question Q-update-link in docs/19-decisions-log.md), so iOS opens the App Store app for now.
enum StoreLinks {
    static let appStore = URL(string: "itms-apps://apps.apple.com")
}

struct MainTabsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    let profile: Profile?

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Wake", systemImage: "alarm.fill", value: AppTab.wake) {
                PlaceholderScreen(title: "Wake", subtitle: "Your next alarm, streak and today's push-ups live here.",
                                  symbol: "alarm.fill", glow: ColorTokens.brandFlame)
            }
            Tab("Battle", systemImage: "bolt.fill", value: AppTab.battle) {
                PlaceholderScreen(title: "Battle", subtitle: "Live split-screen push-up battles are on the way.",
                                  symbol: "bolt.fill", glow: ColorTokens.brandVolt)
            }
            Tab("Clan", systemImage: "shield.fill", value: AppTab.clan) {
                PlaceholderScreen(title: "Clan", subtitle: "Team up and win the weekly Clan War.",
                                  symbol: "shield.fill", glow: ColorTokens.brandCyan)
            }
            Tab("Ranks", systemImage: "trophy.fill", value: AppTab.ranks) {
                PlaceholderScreen(title: "Ranks", subtitle: "Global and friends leaderboards are coming soon.",
                                  symbol: "trophy.fill", glow: ColorTokens.leagueGold)
            }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView(
                    model: ProfileViewModel(
                        profile: profile, profiles: session.profiles, auth: session.auth,
                        onSignedOut: { session.signedOut() },
                        onCreateAccount: { session.createAccountFromGuest() }
                    ),
                    appVersion: Bundle.main.appVersionString
                )
            }
        }
        .tint(Color(ColorTokens.brandFlameText))
    }
}

extension Bundle {
    var appVersionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .environment(AppSession(auth: InMemoryBackend(), profiles: InMemoryBackend(), remoteConfig: nil, appVersion: "1.0.0"))
}
