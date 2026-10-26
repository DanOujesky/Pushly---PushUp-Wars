import Foundation

/// Links people share (D-078). `pushly.app` is not ours (Q-01), so share links point to small pages on the GitHub
/// Pages site that open the app (`pushly://u/<name>`); the apps also parse these URLs (QR scanner, `DeepLink`).
public enum ShareLinks {
    public static let host = "danoujesky.github.io"
    public static let siteFolder = "Pushly---PushUp-Wars"
    public static let base = "https://\(host)/\(siteFolder)/"

    /// `https://danoujesky.github.io/Pushly---PushUp-Wars/u/?n=<username>` — add me as a friend.
    public static func profile(_ username: String) -> URL? {
        var c = URLComponents(string: base + "u/")
        c?.queryItems = [URLQueryItem(name: "n", value: username)]
        return c?.url
    }

    /// The username in a scanned / pasted friend link (share page, pushly://u/…, pushly.app/u/…), or nil.
    public static func username(in text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              case let .user(name)? = DeepLink(url: url) else { return nil }
        return name
    }
}
