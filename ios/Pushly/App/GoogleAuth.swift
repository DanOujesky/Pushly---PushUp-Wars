import Core
import GoogleSignIn
import UIKit

/// Native Google sign-in (D-061): GoogleSignIn SDK → ID token + access token → Supabase `signInWithIdToken`.
/// Client IDs come from Info.plist (`GIDClientID` iOS client, `GIDServerClientID` web client — Backend.xcconfig).
@MainActor
enum GoogleAuth {
    static var isConfigured: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String).map { !$0.isEmpty && !$0.hasPrefix("$(") } ?? false
    }

    /// nil when the user closes the Google sheet.
    static func signIn() async throws -> (idToken: String, accessToken: String)? {
        guard let presenter = topViewController() else { return nil }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { return nil }
            return (idToken, result.user.accessToken.tokenString)
        } catch let error as GIDSignInError where error.code == .canceled {
            return nil
        }
    }

    /// Google's own "G" logo shipped inside the GoogleSignIn SDK bundle (used by its sign-in button), nil if missing.
    static var logo: UIImage? {
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for b in bundles {
            if let url = b.url(forResource: "GoogleSignIn_GoogleSignIn", withExtension: "bundle"),
               let sdk = Bundle(url: url),
               let image = UIImage(named: "google", in: sdk, with: nil) {
                return image
            }
        }
        return nil
    }

    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
