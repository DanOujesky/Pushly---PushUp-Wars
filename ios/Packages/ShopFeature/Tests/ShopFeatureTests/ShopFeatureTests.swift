import Core
import Foundation
import Testing
@testable import ShopFeature

/// Ads + Pushly Pro wiring (D-073): config fallbacks, the ad history behind the caps, paywall copy.
@MainActor
struct ShopFeatureTests {
    @Test func configFallsBackToGoogleTestIDs() {
        let c = ShopConfig(info: ["PushlyAdBannerUnitID": "$(ADMOB_IOS_BANNER_ID)", "RevenueCatAPIKey": ""])
        #expect(c.bannerUnitID == ShopConfig.testBanner)
        #expect(c.interstitialUnitID == ShopConfig.testInterstitial)
        #expect(c.usesTestAds)
        #expect(!c.purchasesAvailable)
    }

    @Test func configUsesRealValues() {
        let c = ShopConfig(info: ["PushlyAdBannerUnitID": "ca-app-pub-123/456", "PushlyAdInterstitialUnitID": "ca-app-pub-123/789",
                                  "RevenueCatAPIKey": "appl_abc"])
        #expect(c.bannerUnitID == "ca-app-pub-123/456")
        #expect(!c.usesTestAds)
        #expect(c.purchasesAvailable)
    }

    @Test func historyKeepsOneWeekForTheCaps() throws {
        let defaults = try #require(UserDefaults(suiteName: "ads-\(UUID().uuidString)"))
        let h = AdHistory(defaults: defaults)
        let day: Int64 = 24 * 3600 * 1000
        h.record("battle_results_interstitial", atMs: 0)
        h.record("battle_results_interstitial", atMs: 8 * day)
        #expect(h.shown.map(\.atMs) == [8 * day])
    }

    @Test func interstitialFollowsAdsGate() {
        var ctx = AdsGate.Context()
        ctx.completedSessions = 5
        ctx.nowMs = 10_000_000
        ctx.battlesSinceInterstitial = 3
        #expect(AdsGate.canShow("battle_results_interstitial", ctx).allowed)
        ctx.isPro = true
        #expect(AdsGate.canShow("battle_results_interstitial", ctx).reason == "pro")
    }

    @Test func plansSortYearlyFirst() {
        let kinds: [PaywallPlan.Kind] = [.monthly, .lifetime, .annual]
        #expect(kinds.sorted { Shop.order($0) < Shop.order($1) } == [.annual, .monthly, .lifetime])
    }

    @Test func renewalTermsMentionTrialAndPrice() {
        let plan = PaywallPlan(id: "y", kind: .annual, price: "19,99 €", trialDays: 7, package: nil)
        let text = PaywallView.terms(plan)
        #expect(text.contains("7 days free"))
        #expect(text.contains("19,99 €"))
        #expect(text.contains("Renews automatically"))
    }
}
