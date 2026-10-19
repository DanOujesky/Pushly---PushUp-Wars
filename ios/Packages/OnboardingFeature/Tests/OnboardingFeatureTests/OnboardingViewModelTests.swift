import Core
import Foundation
import Networking
import Testing
@testable import OnboardingFeature

@MainActor
@Suite("Sign in")
struct SignInViewModelTests {
    @Test func emailCodeFlowSignsIn() async throws {
        let backend = InMemoryBackend()
        let signedIn = Box<UUID>()
        let model = SignInViewModel(auth: backend, onSignedIn: { signedIn.value = $0 })

        model.email = "not-an-email"
        #expect(!model.canSendCode)
        model.email = "  Dan@Example.com "
        #expect(model.canSendCode)
        await model.sendCode()
        #expect(model.step == .enterCode(email: "dan@example.com"))
        #expect(await backend.sentCodes == ["dan@example.com"])

        model.code = "12345"
        #expect(!model.canVerify)
        model.code = "000000"
        await model.verify()
        #expect(model.failure == .invalidCode)
        #expect(signedIn.value == nil)

        model.code = "123456"
        await model.verify()
        #expect(model.failure == nil)
        #expect(signedIn.value != nil)
    }

    @Test func networkErrorIsReported() async {
        let backend = InMemoryBackend()
        await backend.setNextError(AppError(code: .network, message: "offline"))
        let model = SignInViewModel(auth: backend, onSignedIn: { _ in })
        model.email = "dan@example.com"
        await model.sendCode()
        #expect(model.failure == .network)
        #expect(model.step == .enterEmail)
        #expect(!model.isWorking)
    }

    @Test func withoutBackendOnlyGuestIsPossible() async {
        let model = SignInViewModel(auth: nil, onSignedIn: { _ in })
        #expect(!model.isBackendAvailable)
        model.email = "dan@example.com"
        await model.sendCode()
        #expect(model.step == .enterEmail)
        await model.signInWithApple(idToken: "x", nonce: "y")
        #expect(model.failure == .backendUnavailable)
    }

    @Test func appleNonceIsHashed() {
        let raw = AppleNonce.random()
        #expect(raw.count == 32)
        #expect(AppleNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@MainActor
@Suite("Profile setup")
struct ProfileSetupViewModelTests {
    func makeModel(backend: InMemoryBackend, completed: @escaping @MainActor (Profile) -> Void = { _ in }) async throws -> ProfileSetupViewModel {
        _ = try await backend.signInWithApple(idToken: "t", nonce: "n")
        let profile = try await backend.fetchOwnProfile()
        return ProfileSetupViewModel(profile: profile, profiles: backend, currentYear: 2026, regionCode: "CZ",
                                     timeZoneID: "Europe/Prague", debounce: .zero, onCompleted: completed)
    }

    @Test func placeholderUsernameIsNotPrefilled() async throws {
        let model = try await makeModel(backend: InMemoryBackend(currentYear: 2026))
        #expect(model.username.isEmpty)
        #expect(model.country == "CZ")
        #expect(model.birthYearOptions.first == 2010)
    }

    @Test func availabilityAndSubmit() async throws {
        let backend = InMemoryBackend(currentYear: 2026)
        let completed = Box<Profile>()
        let model = try await makeModel(backend: backend) { completed.value = $0 }

        model.username = "a!"
        model.usernameChanged()
        #expect(model.availability == .invalid(.tooShort))

        model.username = "Taken"
        await model.checkAvailability(of: "Taken")
        #expect(model.availability == .taken)

        model.username = "DanPushes"
        await model.checkAvailability(of: "DanPushes")
        #expect(model.availability == .available)
        #expect(!model.canSubmit)  // no birth year yet

        model.birthYear = 2004
        #expect(model.canSubmit)
        await model.submit()
        #expect(model.failure == nil)
        let profile = try #require(completed.value)
        #expect(profile.username == "DanPushes")
        #expect(profile.onboardingCompleted)
        #expect(profile.country == "CZ")
        #expect(profile.timezone == "Europe/Prague")
    }

    @Test func raceOnUsernameIsHandled() async throws {
        let backend = InMemoryBackend(currentYear: 2026)
        let model = try await makeModel(backend: backend)
        model.username = "DanPushes"
        await model.checkAvailability(of: "DanPushes")
        model.birthYear = 2000
        await backend.setNextError(AppError(code: .conflict, message: "taken"))
        await model.submit()
        #expect(model.failure == .usernameTaken)
        #expect(model.availability == .taken)
    }

    @Test func staleAvailabilityResultIsIgnored() async throws {
        let model = try await makeModel(backend: InMemoryBackend(currentYear: 2026))
        model.username = "NewName"
        await model.checkAvailability(of: "OldName")  // response for an earlier text
        #expect(model.availability == .idle)
    }

    @Test func countryListHasFlags() {
        let cz = CountryList.all(locale: Locale(identifier: "en_US")).first { $0.code == "CZ" }
        #expect(cz != nil)
        #expect(cz?.flag == "🇨🇿")
    }
}

/// Reference box for values set from @MainActor callbacks in tests.
@MainActor
final class Box<T> {
    var value: T?
}
