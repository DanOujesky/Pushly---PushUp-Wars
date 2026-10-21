import Core
import Foundation
import Networking
import Observation

/// Top-level app state machine (doc 02 §2): launch → (update required) → welcome/sign-in → profile setup → main tabs.
@MainActor
@Observable
final class AppSession {
    enum State: Equatable {
        case launching
        case updateRequired
        case welcome
        case signIn
        case profileSetup(Profile)
        case main(Profile?)   // nil = guest (alarm only)
    }

    private(set) var state: State = .launching
    private(set) var config: RemoteConfig = .fallback
    /// Set when an email sign-in link could not be used (expired or opened on another device).
    var linkSignInFailed = false

    let auth: (any AuthServicing)?
    let profiles: (any ProfileServicing)?
    /// Alarm sync transport (nil in guest-only builds). Used only while signed in.
    let alarmSync: (any AlarmSyncServicing)?
    /// Rep-log upload, server clock and Wake summary (nil in guest-only builds).
    let repSessions: (any RepSessionServicing)?
    /// Stats tab and achievements (nil in guest-only builds). Needs a signed-in account.
    let stats: (any StatsServicing)?
    /// Friends, feed and leaderboards (nil in guest-only builds).
    let social: (any SocialServicing)?
    /// Clans (nil in guest-only builds).
    let clans: (any ClanServicing)?
    private let remoteConfig: (any RemoteConfigServicing)?
    private let defaults: UserDefaults
    private let appVersion: String
    #if DEBUG
    /// Debug builds only: fixed screen for CI screenshots (`-PushlyDebugScreen <name>` launch argument).
    var debugStartState: State?
    #endif

    private enum Keys {
        static let guest = "session.guestMode"
        static let welcomeSeen = "session.welcomeSeen"
    }

    init(
        auth: (any AuthServicing)?,
        profiles: (any ProfileServicing)?,
        remoteConfig: (any RemoteConfigServicing)?,
        defaults: UserDefaults = .standard,
        appVersion: String,
        alarmSync: (any AlarmSyncServicing)? = nil,
        repSessions: (any RepSessionServicing)? = nil,
        stats: (any StatsServicing)? = nil,
        social: (any SocialServicing)? = nil,
        clans: (any ClanServicing)? = nil
    ) {
        self.clans = clans
        self.social = social
        self.repSessions = repSessions
        self.stats = stats
        self.auth = auth
        self.profiles = profiles
        self.remoteConfig = remoteConfig
        self.defaults = defaults
        self.appVersion = appVersion
        self.alarmSync = alarmSync
    }

    /// Production wiring from Info.plist; without a configured backend the app runs guest-only.
    static func live(bundle: Bundle = .main) -> AppSession {
        #if DEBUG
        if let screen = UserDefaults.standard.string(forKey: "PushlyDebugScreen") {
            return debugScreen(screen)
        }
        #endif
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard let config = BackendConfig.fromInfoPlist(bundle) else {
            PLog.warning("No backend configured — guest-only build", .app)
            return AppSession(auth: nil, profiles: nil, remoteConfig: nil, appVersion: version)
        }
        let backend = SupabaseBackend(config: config)
        return AppSession(auth: backend, profiles: backend, remoteConfig: backend, appVersion: version, alarmSync: backend,
                          repSessions: backend, stats: backend, social: backend, clans: backend)
    }

    func start() async {
        #if DEBUG
        if let debugStartState {
            state = debugStartState
            return
        }
        #endif
        if let remoteConfig, let fetched = try? await remoteConfig.fetch() {
            config = fetched
            if AppVersion.updateRequired(app: appVersion, minSupported: fetched.minSupportedVersion) {
                state = .updateRequired
                return
            }
        }
        await route()
    }

    /// Decides where the user belongs right now.
    func route() async {
        if let auth, await auth.currentUserID() != nil {
            await loadProfileAndRoute()
        } else if defaults.bool(forKey: Keys.guest) {
            state = .main(nil)
        } else {
            state = defaults.bool(forKey: Keys.welcomeSeen) ? .signIn : .welcome
        }
    }

    func welcomeFinished() {
        defaults.set(true, forKey: Keys.welcomeSeen)
        state = .signIn
    }

    func signedIn() async {
        defaults.set(false, forKey: Keys.guest)
        await loadProfileAndRoute()
    }

    /// Email-link sign-in: the link opens the app with `pushly://auth-callback?...`.
    func handleAuthCallback(_ url: URL) async {
        guard let auth else { return }
        do {
            _ = try await auth.handleAuthCallback(url)
            await signedIn()
        } catch {
            PLog.warning("Email link sign-in failed: \(error)", .app)
            linkSignInFailed = true
        }
    }

    func continueAsGuest() {
        defaults.set(true, forKey: Keys.guest)
        state = .main(nil)
    }

    func profileCompleted(_ profile: Profile) {
        state = .main(profile)
    }

    func signedOut() {
        defaults.set(false, forKey: Keys.guest)
        state = .signIn
    }

    func createAccountFromGuest() {
        defaults.set(false, forKey: Keys.guest)
        state = .signIn
    }

    private func loadProfileAndRoute() async {
        guard let profiles else { state = .main(nil); return }
        do {
            let profile = try await profiles.fetchOwnProfile()
            state = profile.onboardingCompleted ? .main(profile) : .profileSetup(profile)
        } catch let error as AppError where error.code == .unauthenticated {
            state = .signIn
        } catch {
            // Offline launch with a stored session: let the user in; screens show cached/empty data.
            PLog.warning("Profile fetch failed at launch: \(error)", .sync)
            state = .main(nil)
        }
    }
}

#if DEBUG
extension AppSession {
    /// Opens one screen with in-memory data, for the screenshot step in `.github/workflows/ios.yml`.
    static func debugScreen(_ name: String) -> AppSession {
        let backend = InMemoryBackend()
        let session = AppSession(auth: backend, profiles: backend, remoteConfig: nil, appVersion: "0.0.0")
        let profile = Profile(id: UUID(), username: "DanPushes", onboardingCompleted: true, avatarPreset: "preset.flame",
                              trophies: 640, level: 7)
        session.debugStartState = switch name {
        case "welcome": .welcome
        case "signIn": .signIn
        case "profileSetup": .profileSetup(Profile(id: UUID(), username: "u_0123456789ab", onboardingCompleted: false))
        case "update": .updateRequired
        case "main", "wake", "wakeSession": .main(profile)
        default: .launching
        }
        return session
    }
}
#endif
