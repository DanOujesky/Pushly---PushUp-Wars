import Core
import Foundation
import Networking
import Testing
@testable import ProfileFeature

@MainActor
@Suite("Profile")
struct ProfileViewModelTests {
    func signedIn() async throws -> (InMemoryBackend, Profile) {
        let backend = InMemoryBackend(currentYear: 2026)
        _ = try await backend.signInWithApple(idToken: "t", nonce: "n")
        let profile = try await backend.updateProfile(ProfilePatch(username: "AnaFit2", birthYear: 2000))
        return (backend, profile)
    }

    @Test func privacyChangesAreSaved() async throws {
        let (backend, profile) = try await signedIn()
        let model = ProfileViewModel(profile: profile, profiles: backend, auth: backend, onSignedOut: {}, onCreateAccount: {})
        await model.setVisibility(.friends)
        await model.setLeaderboardVisible(false)
        #expect(model.profile?.profileVisibility == .friends)
        #expect(model.profile?.leaderboardVisible == false)
        #expect(await backend.profile?.profileVisibility == .friends)
    }

    @Test func failedSaveRollsBack() async throws {
        let (backend, profile) = try await signedIn()
        let model = ProfileViewModel(profile: profile, profiles: backend, auth: backend, onSignedOut: {}, onCreateAccount: {})
        await backend.setNextError(AppError(code: .network, message: "offline"))
        await model.setVisibility(.private)
        #expect(model.profile?.profileVisibility == .public)
        #expect(model.failure == .network)
    }

    @Test func signOutAlwaysCompletesLocally() async throws {
        let (backend, profile) = try await signedIn()
        let signedOut = Flag()
        let model = ProfileViewModel(profile: profile, profiles: backend, auth: backend,
                                     onSignedOut: { signedOut.isSet = true }, onCreateAccount: {})
        await backend.setNextError(AppError(code: .network, message: "offline"))
        await model.signOut()
        #expect(signedOut.isSet)
    }

    @Test func guestMode() {
        let model = ProfileViewModel(profile: nil, profiles: nil, auth: nil, onSignedOut: {}, onCreateAccount: {})
        #expect(model.isGuest)
    }
}

@MainActor
final class Flag {
    var isSet = false
}
