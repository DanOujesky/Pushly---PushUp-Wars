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
}

public protocol ProfileServicing: Sendable {
    func fetchOwnProfile() async throws -> Profile
    func updateProfile(_ patch: ProfilePatch) async throws -> Profile
    func isUsernameAvailable(_ name: String) async throws -> Bool
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
