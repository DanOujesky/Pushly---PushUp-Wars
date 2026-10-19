import Core
import Foundation
import Networking
import Testing
@testable import Pushly

@MainActor
@Suite("AppSession routing")
struct AppSessionTests {
    func freshDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func firstLaunchShowsWelcomeThenSignIn() async {
        let backend = InMemoryBackend()
        let session = AppSession(auth: backend, profiles: backend, remoteConfig: backend, defaults: freshDefaults(), appVersion: "1.0.0")
        await session.start()
        #expect(session.state == .welcome)
        session.welcomeFinished()
        #expect(session.state == .signIn)
    }

    @Test func oldVersionIsBlocked() async {
        let backend = InMemoryBackend()
        await backend.setConfig(RemoteConfig(minSupportedVersion: "1.2.0"))
        let session = AppSession(auth: backend, profiles: backend, remoteConfig: backend, defaults: freshDefaults(), appVersion: "1.1.9")
        await session.start()
        #expect(session.state == .updateRequired)
    }

    @Test func newUserGoesToProfileSetupThenMain() async throws {
        let backend = InMemoryBackend(currentYear: 2026)
        let session = AppSession(auth: backend, profiles: backend, remoteConfig: nil, defaults: freshDefaults(), appVersion: "1.0.0")
        _ = try await backend.signInWithApple(idToken: "t", nonce: "n")
        await session.signedIn()
        guard case .profileSetup = session.state else {
            Issue.record("expected profile setup, got \(session.state)")
            return
        }
        let done = try await backend.updateProfile(ProfilePatch(username: "DanPushes", birthYear: 2001))
        session.profileCompleted(done)
        #expect(session.state == .main(done))

        // Next launch with the stored session goes straight to the tabs.
        let relaunch = AppSession(auth: backend, profiles: backend, remoteConfig: nil, defaults: freshDefaults(), appVersion: "1.0.0")
        await relaunch.start()
        #expect(relaunch.state == .main(done))
    }

    @Test func emailLinkSignsIn() async throws {
        let backend = InMemoryBackend(currentYear: 2026)
        let session = AppSession(auth: backend, profiles: backend, remoteConfig: nil, defaults: freshDefaults(), appVersion: "1.0.0")
        await session.handleAuthCallback(URL(string: "pushly://auth-callback?code=abc")!)
        guard case .profileSetup = session.state else {
            Issue.record("expected profile setup, got \(session.state)")
            return
        }
        #expect(!session.linkSignInFailed)
    }

    @Test func badEmailLinkIsReported() async {
        let backend = InMemoryBackend()
        await backend.setNextError(AppError(code: .unauthenticated, message: "expired"))
        let session = AppSession(auth: backend, profiles: backend, remoteConfig: nil, defaults: freshDefaults(), appVersion: "1.0.0")
        await session.handleAuthCallback(URL(string: "pushly://auth-callback?code=old")!)
        #expect(session.linkSignInFailed)
    }

    @Test func guestModeIsRemembered() async {
        let defaults = freshDefaults()
        let session = AppSession(auth: nil, profiles: nil, remoteConfig: nil, defaults: defaults, appVersion: "1.0.0")
        session.continueAsGuest()
        #expect(session.state == .main(nil))
        let relaunch = AppSession(auth: nil, profiles: nil, remoteConfig: nil, defaults: defaults, appVersion: "1.0.0")
        await relaunch.start()
        #expect(relaunch.state == .main(nil))
        relaunch.createAccountFromGuest()
        #expect(relaunch.state == .signIn)
    }

    @Test func offlineConfigDoesNotBlockLaunch() async {
        let backend = InMemoryBackend()
        await backend.setNextError(AppError(code: .network, message: "offline"))
        let session = AppSession(auth: backend, profiles: backend, remoteConfig: backend, defaults: freshDefaults(), appVersion: "1.0.0")
        await session.start()
        #expect(session.state == .welcome)
    }
}
