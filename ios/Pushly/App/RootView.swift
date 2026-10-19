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
        .task { await session.start() }
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(ColorTokens.bgBase).ignoresSafeArea()
            Text("Pushly")
                .font(.token(TypographyTokens.displayXl))
                .foregroundStyle(LinearGradient(GradientTokens.hero))
        }
    }
}

/// Shown when remote config says this version is no longer supported (doc 03 §7).
struct ForceUpdateView: View {
    var body: some View {
        VStack(spacing: SpacingTokens.l) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color(ColorTokens.brandFlame))
                .accessibilityHidden(true)
            Text("Update required")
                .font(.token(TypographyTokens.displayL))
            Text("This version of Pushly is no longer supported. Please update from the App Store to keep your alarms and progress working.")
                .font(.token(TypographyTokens.body))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(ColorTokens.textSecondary))
        }
        .padding(SpacingTokens.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(ColorTokens.bgBase))
    }
}

struct MainTabsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    let profile: Profile?

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Wake", systemImage: "alarm.fill", value: AppTab.wake) {
                PlaceholderScreen(title: "Wake", subtitle: "Your next alarm and streak live here.")
            }
            Tab("Battle", systemImage: "figure.strengthtraining.traditional", value: AppTab.battle) {
                PlaceholderScreen(title: "Battle", subtitle: "Live push-up battles arrive in Phase 7.")
            }
            Tab("Clan", systemImage: "shield.lefthalf.filled", value: AppTab.clan) {
                PlaceholderScreen(title: "Clan", subtitle: "Clans and Clan Wars arrive in Phase 8.")
            }
            Tab("Ranks", systemImage: "trophy.fill", value: AppTab.ranks) {
                PlaceholderScreen(title: "Ranks", subtitle: "Leaderboards arrive in Phase 6.")
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
        .tint(Color(ColorTokens.brandFlame))
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
