import Core
import Foundation
import GoogleMobileAds
import UserMessagingPlatform

/// Google Mobile Ads + UMP consent (doc 13 §1, D-073). Consent is asked once in the main app (never during
/// onboarding or a wake flow); ads start only when UMP says ads may be requested. Without consent for
/// personalised ads, Google serves non-personalised ads. No ATT prompt: Pushly never asks to track (D-073).
@MainActor
@Observable
public final class AdsManager: NSObject {
    public let config: ShopConfig
    /// UMP allows requesting ads (consent given / not needed).
    public private(set) var canRequestAds = false
    /// Show the "Ad privacy settings" entry (EU users can change their choice any time).
    public private(set) var privacyOptionsRequired = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var interstitialLoadedAt: Date?
    @ObservationIgnored private let history = AdHistory()

    public init(config: ShopConfig) {
        self.config = config
    }

    /// Asks UMP (shows the consent form only when the user hasn't answered yet and it's required), then starts the
    /// SDK. Safe to call more than once.
    public func start() async {
        guard !AppActivity.wakeActive else { return }
        let info = ConsentInformation.shared
        do {
            try await info.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            PLog.warning("Consent flow failed: \(error)", .ads)
        }
        privacyOptionsRequired = info.privacyOptionsRequirementStatus == .required
        canRequestAds = info.canRequestAds
        guard canRequestAds, !started else { return }
        started = true
        _ = await MobileAds.shared.start()
        await preloadInterstitial()
    }

    /// "Ad privacy settings" in Profile → Account (UMP privacy options form).
    public func showPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        } catch {
            PLog.warning("Privacy options failed: \(error)", .ads)
        }
        canRequestAds = ConsentInformation.shared.canRequestAds
    }

    /// Whether a banner may show on this screen right now.
    func bannerAllowed(_ placement: String) -> Bool {
        canRequestAds && AdsGate.canShow(placement, AdContext.current(history: history)).allowed
    }

    // MARK: interstitial (battle results, doc 13 §1)

    private func preloadInterstitial() async {
        guard canRequestAds, !Monetization.isPro else { return }
        if let loaded = interstitialLoadedAt, interstitial != nil, Date().timeIntervalSince(loaded) < 3600 { return }
        do {
            let ad = try await InterstitialAd.load(with: config.interstitialUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            interstitial = ad
            interstitialLoadedAt = Date()
        } catch {
            PLog.info("Interstitial not loaded: \(error)", .ads)
        }
    }

    /// Called when the user closes a battle's result screen. Counts the battle; shows an interstitial only when
    /// AdsGate allows (1 per 3 battles, 4 min apart, 6 a day, never for Pro, never near a wake flow).
    func battleClosed() {
        AppActivity.battleFinished()
        let check = AdsGate.canShow("battle_results_interstitial", AdContext.current(history: history))
        guard canRequestAds, check.allowed, let ad = interstitial else {
            Task { await preloadInterstitial() }
            return
        }
        interstitial = nil
        history.record("battle_results_interstitial", atMs: Int64(Date().timeIntervalSince1970 * 1000))
        AppActivity.interstitialShown()
        ad.present(from: nil)
    }
}

extension AdsManager: FullScreenContentDelegate {
    nonisolated public func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor in await self.preloadInterstitial() }
    }

    nonisolated public func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        Task { @MainActor in await self.preloadInterstitial() }
    }
}
