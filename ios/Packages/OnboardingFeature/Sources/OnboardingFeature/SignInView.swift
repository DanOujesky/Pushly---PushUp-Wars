import AuthenticationServices
import CryptoKit
import DesignSystem
import Networking
import SwiftUI

/// Sign-in (doc 02 PS-02): Sign in with Apple, email one-time code, or continue as guest (alarm only).
public struct SignInView: View {
    @State private var model: SignInViewModel
    @State private var appleNonce = ""
    let onGuest: () -> Void
    let linkFailed: Bool

    public init(model: SignInViewModel, linkFailed: Bool = false, onGuest: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.linkFailed = linkFailed
        self.onGuest = onGuest
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.l) {
                Text("Sign in")
                    .font(.token(TypographyTokens.displayL))
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text("Your push-ups, streaks and trophies are saved to your account.")
                    .font(.token(TypographyTokens.body))
                    .foregroundStyle(Color(ColorTokens.textSecondary))

                if !model.isBackendAvailable {
                    InlineBanner("This build isn't connected to a server yet. You can still use the alarm as a guest.",
                                 kind: .warning)
                }

                if linkFailed {
                    InlineBanner("That sign-in link has expired or was opened on another device. Request a new email.")
                }

                if let failure = model.failure {
                    InlineBanner(Self.message(for: failure))
                }

                switch model.step {
                case .enterEmail: emailStep
                case let .enterCode(email): codeStep(email: email)
                }

                if model.isBackendAvailable, model.step == .enterEmail {
                    divider
                    appleButton
                }

                Button(action: onGuest) {
                    Text("Continue as guest (alarm only)")
                        .font(.token(TypographyTokens.bodyS))
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                }
            }
            .padding(SpacingTokens.gutter)
        }
        .background(Color(ColorTokens.bgBase))
        .disabled(model.isWorking)
    }

    private var emailStep: some View {
        VStack(spacing: SpacingTokens.sm) {
            PushlyTextField("Email", text: $model.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PrimaryButton("Email me a sign-in link", isLoading: model.isWorking) {
                Task { await model.sendCode() }
            }
            .disabled(!model.canSendCode || !model.isBackendAvailable)
        }
    }

    private func codeStep(email: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Text("We sent an email to \(email). Open it on this phone and tap the sign-in link — or enter the code if the email shows one.")
                .font(.token(TypographyTokens.body))
                .foregroundStyle(Color(ColorTokens.textPrimary))
            PushlyTextField("Code from the email", text: $model.code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
            PrimaryButton("Verify", isLoading: model.isWorking) {
                Task { await model.verify() }
            }
            .disabled(!model.canVerify)
            HStack {
                Button("Use another email") { model.changeEmail() }
                Spacer()
                Button("Resend code") { Task { await model.sendCodeAgain() } }
            }
            .font(.token(TypographyTokens.bodyS))
            .frame(minHeight: TouchTarget.minimum)
        }
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(Color(ColorTokens.strokeSubtle)).frame(height: 1)
            Text("or").font(.token(TypographyTokens.caption)).foregroundStyle(Color(ColorTokens.textTertiary))
            Rectangle().fill(Color(ColorTokens.strokeSubtle)).frame(height: 1)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = AppleNonce.random()
            appleNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = AppleNonce.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let token = String(data: tokenData, encoding: .utf8) else {
                    model.appleSignInFailed()
                    return
                }
                let nonce = appleNonce
                Task { await model.signInWithApple(idToken: token, nonce: nonce) }
            case let .failure(error):
                // The user closing the sheet is not an error worth showing.
                if (error as? ASAuthorizationError)?.code != .canceled { model.appleSignInFailed() }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.m))
    }

    static func message(for failure: SignInViewModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .invalidCode: "That code didn't work. Check it or request a new one."
        case .network: "No connection. Check your internet and try again."
        case .backendUnavailable: "Sign-in isn't available in this build."
        case .generic: "Something went wrong. Please try again."
        }
    }
}

/// Nonce for Sign in with Apple: the raw value goes to Supabase, its SHA-256 to Apple.
enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset[Int.random(in: 0..<charset.count, using: &generator)] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    SignInView(model: SignInViewModel(auth: InMemoryBackend(), onSignedIn: { _ in }), onGuest: {})
}
