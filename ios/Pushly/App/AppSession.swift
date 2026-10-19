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

    let auth: (any AuthServicing)?
    let profiles: (any ProfileServicing)?
    private let remoteConfig: (any RemoteConfigServicing)?
    private let defaults: UserDefaults
    private let appVersion: String

    private enum Keys {
        static let guest = "session.guestMode"
        static let welcomeSeen = "session.welcomeSeen"
    }

    init(
        auth: (any AuthServicing)?,
        profiles: (any ProfileServicing)?,
        remoteConfig: (any RemoteConfigServicing)?,
        defaults: UserDefaults = .standard,
        appVersion: String
    ) {
        self.auth = auth
        self.profiles = profiles
        self.remoteConfig = remoteConfig
        self.defaults = defaults
        self.appVersion = appVersion
    }

    /// Production wiring from Info.plist; without a configured backend the app runs guest-only.
    static func live(bundle: Bundle = .main) -> AppSession {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard let config = BackendConfig.fromInfoPlist(bundle) else {
            PLog.warning("No backend configured — guest-only build", .app)
            return AppSession(auth: nil, profiles: nil, remoteConfig: nil, appVersion: version)
        }
        let backend = SupabaseBackend(config: config)
        return AppSession(auth: backend, profiles: backend, remoteConfig: backend, appVersion: version)
    }

    func start() async {
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
