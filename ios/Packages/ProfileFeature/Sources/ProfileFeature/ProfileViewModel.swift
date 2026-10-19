import Core
import Foundation
import Networking
import Observation

/// Profile tab + privacy settings (doc 02 PS-70, PS-73). Stats, achievements and friends arrive in later phases.
@MainActor
@Observable
public final class ProfileViewModel {
    public enum Failure: Equatable, Sendable { case network, generic }

    public private(set) var profile: Profile?
    public private(set) var isSaving = false
    public private(set) var failure: Failure?

    private let profiles: (any ProfileServicing)?
    private let auth: (any AuthServicing)?
    private let onSignedOut: @MainActor () -> Void
    private let onCreateAccount: @MainActor () -> Void

    /// `profile == nil` means guest mode.
    public init(
        profile: Profile?,
        profiles: (any ProfileServicing)?,
        auth: (any AuthServicing)?,
        onSignedOut: @escaping @MainActor () -> Void,
        onCreateAccount: @escaping @MainActor () -> Void
    ) {
        self.profile = profile
        self.profiles = profiles
        self.auth = auth
        self.onSignedOut = onSignedOut
        self.onCreateAccount = onCreateAccount
    }

    public var isGuest: Bool { profile == nil }

    public func refresh() async {
        guard let profiles, profile != nil else { return }
        if let fresh = try? await profiles.fetchOwnProfile() { profile = fresh }
    }

    public func setVisibility(_ visibility: ProfileVisibility) async {
        await save(ProfilePatch(profileVisibility: visibility)) { $0.profileVisibility = visibility }
    }

    public func setLeaderboardVisible(_ visible: Bool) async {
        await save(ProfilePatch(leaderboardVisible: visible)) { $0.leaderboardVisible = visible }
    }

    public func signOut() async {
        do {
            try await auth?.signOut()
        } catch {
            // Signing out locally must always work; the server session expires on its own.
            PLog.warning("Sign-out request failed; clearing local session anyway", .app)
        }
        onSignedOut()
    }

    public func createAccount() {
        onCreateAccount()
    }

    /// Optimistic update: apply locally, roll back if the server rejects it.
    private func save(_ patch: ProfilePatch, apply: (inout Profile) -> Void) async {
        guard let profiles, var optimistic = profile else { return }
        let previous = optimistic
        apply(&optimistic)
        profile = optimistic
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            profile = try await profiles.updateProfile(patch)
        } catch let error as AppError {
            profile = previous
            failure = error.code == .network ? .network : .generic
        } catch {
            profile = previous
            failure = .generic
        }
    }
}
