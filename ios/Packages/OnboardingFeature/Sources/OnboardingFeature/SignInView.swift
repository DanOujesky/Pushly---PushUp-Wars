import AuthenticationServices
import CryptoKit
import DesignSystem
import Networking
import SwiftUI

/// Sign-in (doc 02 PS-02): Sign in with Apple, email one-time code, or continue as guest (alarm only).
public struct SignInView: View {
    /// Native Google sign-in done by the app (GoogleSignIn SDK). Returns nil when the user closes the sheet.
    public typealias GoogleSignIn = @MainActor () async throws -> (idToken: String, accessToken: String)?

    @State private var model: SignInViewModel
    @State private var appleNonce = ""
    let onGuest: () -> Void
    let linkFailed: Bool
    let google: GoogleSignIn?

    public init(model: SignInViewModel, linkFailed: Bool = false, google: GoogleSignIn? = nil, onGuest: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.linkFailed = linkFailed
        self.google = google
        self.onGuest = onGuest
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.l) {
                switch model.step {
                case .enterEmail: emailHeader
                case let .enterCode(email): codeHeader(email: email)
                }

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
                case .enterEmail:
                    VStack(spacing: SpacingTokens.sm) {
                        if model.isBackendAvailable {
                            appleButton
                            if google != nil { googleButton }
                            divider
                        }
                        emailStep
                    }
                case .enterCode:
                    codeStep
                }
            }
            .padding(.horizontal, SpacingTokens.l)
            .padding(.top, SpacingTokens.xxxl)
            .padding(.bottom, SpacingTokens.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            GhostButton("Just the alarm for now — continue as guest", action: onGuest)
                .padding(.horizontal, SpacingTokens.l)
                .padding(.bottom, SpacingTokens.s)
        }
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .topTrailing, offset: CGSize(width: 220, height: -220))
        .disabled(model.isWorking)
    }

    private var emailHeader: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            ScreenTitle("Join the\narena", token: TypographyTokens.displayXl)
            Text("Save your streaks, trophies and every push-up you do.")
                .typography(TypographyTokens.body)
                .foregroundStyle(Color(ColorTokens.textSecondary))
        }
        .padding(.bottom, SpacingTokens.s)
    }

    private func codeHeader(email: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(GradientTokens.hero))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Glow.flame, radius: 16, y: 10)
                .accessibilityHidden(true)
                .padding(.bottom, SpacingTokens.s)
            ScreenTitle("Check your\ninbox", token: TypographyTokens.displayXl)
            Text("We sent an email to \(email). Open it on this phone and tap the sign-in link — or enter the code if the email shows one.")
                .typography(TypographyTokens.body)
                .foregroundStyle(Color(ColorTokens.textSecondary))
        }
    }

    private var emailStep: some View {
        VStack(spacing: SpacingTokens.m) {
            PushlyTextField("Email", placeholder: "you@example.com", text: $model.email)
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

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            PushlyTextField("Code from the email", placeholder: "123456", text: $model.code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
            PrimaryButton("Verify", isLoading: model.isWorking) {
                Task { await model.verify() }
            }
            .disabled(!model.canVerify)
            HStack {
                GhostButton("Use another email") { model.changeEmail() }
                Spacer()
                GhostButton("Resend code") { Task { await model.sendCodeAgain() } }
            }
        }
    }

    private var divider: some View {
        HStack(spacing: SpacingTokens.sm) {
            Rectangle().fill(Color(ColorTokens.strokeSubtle)).frame(height: 1)
            Text("or with email")
                .typography(TypographyTokens.overline)
                .foregroundStyle(Color(ColorTokens.textDisabled))
                .fixedSize()
            Rectangle().fill(Color(ColorTokens.strokeSubtle)).frame(height: 1)
        }
        .padding(.vertical, SpacingTokens.s)
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
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.m))
    }

    private var googleButton: some View {
        Button {
            guard let google else { return }
            Task {
                do {
                    if let tokens = try await google() {
                        await model.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
                    }
                } catch {
                    model.appleSignInFailed()
                }
            }
        } label: {
            HStack(spacing: SpacingTokens.s) {
                Text(verbatim: "G").typography(TypographyTokens.titleM).accessibilityHidden(true)
                Text("Continue with Google").typography(TypographyTokens.button)
            }
            .foregroundStyle(Color(ColorTokens.bgBase))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color(ColorTokens.textPrimary), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        }
        .buttonStyle(.plain)
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
        .preferredColorScheme(.dark)
}
