import Core
import Foundation
import Networking
import Observation

/// Sign-in screen logic (doc 02 PS-02): email one-time code and Sign in with Apple.
@MainActor
@Observable
public final class SignInViewModel {
    public enum Step: Equatable, Sendable {
        case enterEmail
        case enterCode(email: String)
    }

    public enum Failure: Equatable, Sendable {
        case invalidCode, network, backendUnavailable, generic
    }

    public var email = ""
    public var code = ""
    public private(set) var step: Step = .enterEmail
    public private(set) var isWorking = false
    public private(set) var failure: Failure?

    private let auth: (any AuthServicing)?
    private let onSignedIn: @MainActor (UUID) -> Void

    /// `auth == nil` means this build has no backend configured — only guest mode is possible.
    public init(auth: (any AuthServicing)?, onSignedIn: @escaping @MainActor (UUID) -> Void) {
        self.auth = auth
        self.onSignedIn = onSignedIn
    }

    public var isBackendAvailable: Bool { auth != nil }

    public var canSendCode: Bool { !isWorking && EmailRules.isPlausible(email) }

    public var canVerify: Bool { !isWorking && code.count == 6 && code.allSatisfy(\.isNumber) }

    public func sendCode() async {
        guard let auth, canSendCode else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        await run {
            try await auth.sendEmailCode(to: address)
            self.code = ""
            self.step = .enterCode(email: address)
        }
    }

    /// Re-sends the code to the address of the current code step.
    public func sendCodeAgain() async {
        guard let auth, case let .enterCode(address) = step else { return }
        await run { try await auth.sendEmailCode(to: address) }
    }

    public func verify() async {
        guard let auth, case let .enterCode(address) = step, canVerify else { return }
        let entered = code
        await run {
            let id = try await auth.verifyEmailCode(email: address, code: entered)
            self.onSignedIn(id)
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async {
        guard let auth else { failure = .backendUnavailable; return }
        await run {
            let id = try await auth.signInWithApple(idToken: idToken, nonce: nonce)
            self.onSignedIn(id)
        }
    }

    public func signInWithGoogle(idToken: String, accessToken: String) async {
        guard let auth else { failure = .backendUnavailable; return }
        await run {
            let id = try await auth.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            self.onSignedIn(id)
        }
    }

    public func appleSignInFailed() {
        failure = .generic
    }

    public func changeEmail() {
        step = .enterEmail
        code = ""
        failure = nil
    }

    private func run(_ body: @MainActor () async throws -> Void) async {
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try await body()
        } catch let error as AppError {
            failure = switch error.code {
            case .unauthenticated, .validationFailed: .invalidCode
            case .network: .network
            default: .generic
            }
        } catch {
            failure = .generic
        }
    }
}

public enum EmailRules {
    /// Deliberately loose: the server validates; this only enables the button.
    public static func isPlausible(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]{2,}/) != nil
    }
}
