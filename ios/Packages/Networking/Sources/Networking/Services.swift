import Core
import Foundation

/// Authentication (doc 02 PS-02). Implementations: `SupabaseBackend` (real), fakes in tests.
public protocol AuthServicing: Sendable {
    /// The signed-in user, if a valid session exists (restored from the keychain on launch).
    func currentUserID() async -> UUID?
    /// Emits the user id whenever the auth state changes (nil = signed out).
    func authStateChanges() -> AsyncStream<UUID?>
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws -> UUID
    func signInWithApple(idToken: String, nonce: String) async throws -> UUID
    func signOut() async throws
    /// Completes a sign-in from an email link (`pushly://auth-callback?...`). Returns the signed-in user.
    func handleAuthCallback(_ url: URL) async throws -> UUID
}

public enum AuthCallback {
    /// Redirect target of sign-in emails. Must be in Supabase `additional_redirect_urls` (supabase/config.toml).
    public static let url: URL = URL(string: "pushly://auth-callback") ?? URL(filePath: "/")

    public static func matches(_ url: URL) -> Bool {
        url.scheme == "pushly" && url.host == "auth-callback"
    }
}

public protocol ProfileServicing: Sendable {
    func fetchOwnProfile() async throws -> Profile
    func updateProfile(_ patch: ProfilePatch) async throws -> Profile
    func isUsernameAvailable(_ name: String) async throws -> Bool
}

/// `sync_alarms` RPC (roadmap P2-09). Payloads are the JSON of `AlarmSync.Change` / `AlarmSync.Response` (AlarmDomain),
/// passed through as data so Networking doesn't depend on the alarm domain.
public protocol AlarmSyncServicing: Sendable {
    func syncAlarms(_ changes: Data) async throws -> Data
}

/// Rep sessions + Wake tab (roadmap P4-03/P4-05/P4-06). Payloads are the JSON of shared/contracts (rep-log,
/// submit-rep-session response, wake-summary), passed through as data so Networking stays feature-agnostic.
/// Errors are `AppError`s; `retryable` tells the outbox whether to try again (doc 03 §5).
public protocol RepSessionServicing: Sendable {
    func submitRepSession(_ log: Data) async throws -> Data
    func wakeSummary() async throws -> Data
    /// Server time (epoch ms) from the `health` function — the anchor for rep timestamps (doc 06 §3).
    func serverTimeMs() async throws -> Int64
}

public protocol RemoteConfigServicing: Sendable {
    func fetch() async throws -> RemoteConfig
}

/// Backend connection settings, read from Info.plist keys `SupabaseURL` / `SupabaseAnonKey` (set via xcconfig).
public struct BackendConfig: Sendable, Equatable {
    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Nil when the build has no backend configured (e.g. CI or a fresh checkout without Secrets.xcconfig):
    /// the app then runs in offline/guest mode and says so on the sign-in screen.
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> BackendConfig? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !key.isEmpty, !rawURL.contains("$("),
              let url = URL(string: rawURL), url.scheme?.hasPrefix("http") == true, url.host != nil
        else { return nil }
        return BackendConfig(url: url, anonKey: key)
    }
}
