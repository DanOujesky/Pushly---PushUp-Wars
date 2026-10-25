import Foundation

/// Ad unit IDs and the RevenueCat key, read from Info.plist (filled from ios/Config/Monetization.xcconfig; real values
/// come from CI variables — doc 13 §1, D-073). Defaults are Google's public test IDs, so debug builds never show
/// real ads and nothing breaks before the AdMob account exists.
public struct ShopConfig: Equatable, Sendable {
    public var bannerUnitID: String
    public var interstitialUnitID: String
    /// RevenueCat public SDK key ("appl_…"); empty = Pro purchases not available yet.
    public var revenueCatKey: String

    public static let testBanner = "ca-app-pub-3940256099942544/2435281174"
    public static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"
    static let testPublisher = "ca-app-pub-3940256099942544"

    public init(bannerUnitID: String, interstitialUnitID: String, revenueCatKey: String) {
        self.bannerUnitID = bannerUnitID
        self.interstitialUnitID = interstitialUnitID
        self.revenueCatKey = revenueCatKey
    }

    /// From an Info.plist dictionary; blank or unresolved (`$(…)`) values fall back to test IDs / "no key".
    public init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let v = (info[key] as? String)?.trimmingCharacters(in: .whitespaces), !v.isEmpty, !v.hasPrefix("$(") else {
                return nil
            }
            return v
        }
        self.init(bannerUnitID: value("PushlyAdBannerUnitID") ?? Self.testBanner,
                  interstitialUnitID: value("PushlyAdInterstitialUnitID") ?? Self.testInterstitial,
                  revenueCatKey: value("RevenueCatAPIKey") ?? "")
    }

    public static var main: ShopConfig { ShopConfig(info: Bundle.main.infoDictionary ?? [:]) }

    /// Google test ads (debug / before the AdMob account): shown with a "Test ad" label.
    public var usesTestAds: Bool { bannerUnitID.hasPrefix(Self.testPublisher) }

    public var purchasesAvailable: Bool { revenueCatKey.hasPrefix("appl_") }
}
