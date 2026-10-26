import AuthenticationServices
import Core
import CryptoKit
import DesignSystem
import Networking
import SwiftUI

/// Sign-in (doc 02 PS-02, D-078): brand header, what an account keeps, a card with Sign in with Apple, Continue with
/// Google (Google's own "G" from the SDK) and email, a legal line, guest at the bottom. Same layout as Android.
public struct SignInView: View {
    /// Native Google sign-in done by the app (GoogleSignIn SDK). Returns nil when the user closes the sheet.
    public typealias GoogleSignIn = @MainActor () async throws -> (idToken: String, accessToken: String)?

    @State private var model: SignInViewModel
    @State private var appleNonce = ""
    let onGuest: () -> Void
    let linkFailed: Bool
    let google: GoogleSignIn?
    let googleLogo: Image?

    public init(model: SignInViewModel, linkFailed: Bool = false, google: GoogleSignIn? = nil, googleLogo: Image? = nil,
                onGuest: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.linkFailed = linkFailed
        self.google = google
        self.googleLogo = googleLogo
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
                    VStack(spacing: SpacingTokens.m) {
                        if model.isBackendAvailable {
                            appleButton
                            if google != nil { googleButton }
                            divider
                        }
                        emailStep
                    }
                    .padding(SpacingTokens.l)
                    .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.xl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: RadiusTokens.xl, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
                    legalLine
                case .enterCode:
                    codeStep
                }
            }
            .padding(.horizontal, SpacingTokens.l)
            .padding(.top, SpacingTokens.xl)
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
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            HStack(spacing: SpacingTokens.sm) {
                LogoMark(size: 44)
                Wordmark(token: TypographyTokens.titleL)
            }
            .accessibilityHidden(true)
            ScreenTitle("Join the\narena", token: TypographyTokens.displayXl)
            Text("Save your streaks, trophies and every push-up you do.")
                .typography(TypographyTokens.body)
                .foregroundStyle(Color(ColorTokens.textSecondary))
            HStack(spacing: SpacingTokens.s) {
                perk("🏆", "Keep your trophies")
                perk("⚔️", "Battle friends")
                perk("🛡️", "Join a clan")
            }
        }
        .padding(.bottom, SpacingTokens.s)
    }

    private func perk(_ glyph: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: glyph).font(.title2).accessibilityHidden(true)
            Text(label)
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpacingTokens.sm)
        .padding(.horizontal, SpacingTokens.xs)
        .background(Color(ColorTokens.bgSurface).opacity(0.8), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .accessibilityElement(children: .combine)
    }

    private var legalLine: some View {
        HStack(spacing: 4) {
            Text("By continuing you accept the")
            Link("Terms", destination: LegalLinks.terms)
            Text(verbatim: "·")
            Link("Privacy", destination: LegalLinks.privacy)
        }
        .typography(TypographyTokens.caption)
        .foregroundStyle(Color(ColorTokens.textTertiary))
        .tint(Color(ColorTokens.brandFlameText))
        .frame(maxWidth: .infinity)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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
            Text("We'll email you a link — no password needed.")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(height: 56)
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
            // Google's light button: white, the official "G" from the SDK, dark text
            HStack(spacing: SpacingTokens.sm) {
                if let googleLogo {
                    googleLogo.resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                }
                Text("Continue with Google").font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.white, in: RoundedRectangle(cornerRadius: RadiusTokens.m))
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
