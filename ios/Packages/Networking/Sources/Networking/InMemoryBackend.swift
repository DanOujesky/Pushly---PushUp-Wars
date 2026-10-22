import Core
import Foundation

/// In-memory backend for SwiftUI previews and unit tests. Mirrors the server rules that matter for the UI
/// (username uniqueness, age gate, onboarding completion) so view models can be tested without a network.
public actor InMemoryBackend: AuthServicing, ProfileServicing, RemoteConfigServicing {
    public private(set) var userID: UUID?
    public private(set) var profile: Profile?
    public private(set) var sentCodes: [String] = []
    public var takenUsernames: Set<String> = ["taken", "anafit"]
    public var config = RemoteConfig(minSupportedVersion: "0.0.0")
    public var nextError: AppError?
    public var validCode = "123456"
    public var currentYear: Int

    private var continuations: [UUID: AsyncStream<UUID?>.Continuation] = [:]

    public init(signedInAs profile: Profile? = nil, currentYear: Int = Calendar.current.component(.year, from: Date())) {
        self.profile = profile
        self.userID = profile?.id
        self.currentYear = currentYear
    }

    public func setNextError(_ error: AppError?) { nextError = error }
    public func setConfig(_ config: RemoteConfig) { self.config = config }

    private func failIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    // MARK: Auth

    public func currentUserID() async -> UUID? { userID }

    public nonisolated func authStateChanges() -> AsyncStream<UUID?> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id: id) } }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<UUID?>.Continuation) {
        continuations[id] = continuation
        continuation.yield(userID)
    }

    private func unregister(id: UUID) { continuations[id] = nil }

    private func emit() { for c in continuations.values { c.yield(userID) } }

    public func sendEmailCode(to email: String) async throws {
        try failIfNeeded()
        sentCodes.append(email)
    }

    public func verifyEmailCode(email: String, code: String) async throws -> UUID {
        try failIfNeeded()
        guard code == validCode else { throw AppError(code: .unauthenticated, message: "invalid code") }
        return signIn()
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        try failIfNeeded()
        return signIn()
    }

    public func signInWithGoogle(idToken: String, accessToken: String) async throws -> UUID {
        try failIfNeeded()
        return signIn()
    }

    private func signIn() -> UUID {
        let id = profile?.id ?? UUID()
        if profile == nil {
            profile = Profile(id: id, username: "u_" + String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().suffix(12)),
                              onboardingCompleted: false)
        }
        userID = id
        emit()
        return id
    }

    public func handleAuthCallback(_ url: URL) async throws -> UUID {
        try failIfNeeded()
        guard AuthCallback.matches(url) else { throw AppError(code: .validationFailed, message: "not an auth callback") }
        return signIn()
    }

    public func signOut() async throws {
        try failIfNeeded()
        userID = nil
        emit()
    }

    // MARK: Profile

    public func fetchOwnProfile() async throws -> Profile {
        try failIfNeeded()
        guard userID != nil, let profile else { throw AppError(code: .unauthenticated, message: "signed out") }
        return profile
    }

    public func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        try failIfNeeded()
        guard userID != nil, var p = profile else { throw AppError(code: .unauthenticated, message: "signed out") }
        if let name = patch.username {
            if let error = AccountRules.usernameError(name) {
                throw AppError(code: .validationFailed, message: error.rawValue)
            }
            if takenUsernames.contains(name.lowercased()) { throw AppError(code: .conflict, message: "taken") }
            p.username = name
        }
        if let year = patch.birthYear {
            if AccountRules.birthYearError(year, currentYear: currentYear) != nil {
                throw AppError(code: .validationFailed, message: "minimum age is 16")
            }
            p.birthYear = year
        }
        if let v = patch.avatarPreset { p.avatarPreset = v }
        if let v = patch.country { p.country = v.uppercased() }
        if let v = patch.timezone { p.timezone = v }
        if let v = patch.profileVisibility { p.profileVisibility = v }
        if let v = patch.leaderboardVisible { p.leaderboardVisible = v }
        p.onboardingCompleted = p.onboardingCompleted || (p.birthYear != nil && AccountRules.usernameError(p.username) == nil)
        profile = p
        return p
    }

    public func isUsernameAvailable(_ name: String) async throws -> Bool {
        try failIfNeeded()
        return AccountRules.usernameError(name) == nil && !takenUsernames.contains(name.lowercased())
    }

    // MARK: Config

    public func fetch() async throws -> RemoteConfig {
        try failIfNeeded()
        return config
    }
}
