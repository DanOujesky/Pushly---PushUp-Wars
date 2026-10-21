import Foundation

/// Public legal + support pages (GitHub Pages site built from docs/legal by tools/site). Same URLs on Android.
public enum LegalLinks {
    /// Version of the Terms / Privacy Policy the user accepts on the welcome screen (docs/legal effective date).
    public static let version = "2026-10-21"

    public static let base = "https://danoujesky.github.io/Pushly---PushUp-Wars/"
    public static let privacy = page("privacy.html")
    public static let terms = page("terms.html")
    public static let community = page("community.html")
    public static let deleteAccount = page("delete-account.html")
    public static let support = page("support.html")
    public static let supportEmail = "dany.oujesky@gmail.com"

    private static func page(_ path: String) -> URL {
        URL(string: base + path) ?? URL(fileURLWithPath: "/")
    }
}
