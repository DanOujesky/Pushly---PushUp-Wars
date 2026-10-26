package app.pushly.feature.shop

import android.app.Activity
import android.content.Context
import app.pushly.core.common.AdsGate
import app.pushly.core.common.AppActivity
import app.pushly.core.common.Monetization
import app.pushly.core.common.PLog
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** Ad unit IDs and the RevenueCat key (BuildConfig of the app; Google test IDs until the real ones exist, D-073). */
data class ShopConfig(val bannerUnitId: String, val interstitialUnitId: String, val revenueCatKey: String) {
    /** Google test ads (debug / before the AdMob account): shown with a "Test ad" label. */
    val usesTestAds: Boolean get() = bannerUnitId.startsWith(TEST_PUBLISHER)
    val purchasesAvailable: Boolean get() = revenueCatKey.startsWith("goog_")

    companion object {
        const val TEST_PUBLISHER = "ca-app-pub-3940256099942544"
        const val TEST_BANNER = "ca-app-pub-3940256099942544/9214589741"
        const val TEST_INTERSTITIAL = "ca-app-pub-3940256099942544/1033173712"

        /** Blank values fall back to Google's test IDs / no key. */
        fun of(banner: String, interstitial: String, revenueCat: String) = ShopConfig(
            banner.ifBlank { TEST_BANNER }, interstitial.ifBlank { TEST_INTERSTITIAL }, revenueCat.trim(),
        )
    }
}

/** Full-screen ads shown on this device in the last 7 days (AdsGate caps), persisted through [AppActivity.Store]-like prefs. */
class AdHistory(private val read: () -> String?, private val write: (String) -> Unit) {
    private val serializer = ListSerializer(AdsGate.Shown.serializer())

    val shown: List<AdsGate.Shown>
        get() = read()?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() } ?: emptyList()

    fun record(placement: String, atMs: Long) {
        val week = 7L * 24 * 3600 * 1000
        write(Json.encodeToString(serializer, (shown + AdsGate.Shown(placement, atMs)).filter { atMs - it.atMs < week }))
    }
}

/** The AdsGate context from what the app is doing right now (doc 13 §1). */
internal fun adContext(history: AdHistory, nowMs: Long = System.currentTimeMillis()) = AdsGate.Context(
    isPro = Monetization.isPro,
    wakeActive = AppActivity.wakeActive,
    lastWakeEndedMs = AppActivity.lastWakeEndedMs,
    cameraActive = AppActivity.cameraActive,
    battlePhase = AppActivity.battlePhase,
    completedSessions = AppActivity.completedSessions,
    nowMs = nowMs,
    shown = history.shown,
    battlesSinceInterstitial = AppActivity.battlesSinceInterstitial,
)

/**
 * Google Mobile Ads + UMP consent (doc 13 §1, D-073), same as iOS `AdsManager`. Consent is asked once in the main app
 * (never during onboarding or a wake flow); ads start only when UMP says ads may be requested. Without consent for
 * personalised ads, Google serves non-personalised ads. Main thread only.
 */
class AdsManager(private val context: Context, val config: ShopConfig, private val history: AdHistory) {
    private val _canRequestAds = MutableStateFlow(false)
    val canRequestAds: StateFlow<Boolean> = _canRequestAds.asStateFlow()
    private val _privacyOptionsRequired = MutableStateFlow(false)
    val privacyOptionsRequired: StateFlow<Boolean> = _privacyOptionsRequired.asStateFlow()
    private val consent: ConsentInformation = UserMessagingPlatform.getConsentInformation(context)
    private var started = false
    private var interstitial: InterstitialAd? = null
    private var interstitialLoadedAt = 0L

    /** Asks UMP (the form shows only when it's required and unanswered), then starts the SDK. Safe to call again. */
    fun start(activity: Activity) {
        if (AppActivity.wakeActive) return
        consent.requestConsentInfoUpdate(activity, ConsentRequestParameters.Builder().build(), {
            UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { error ->
                if (error != null) PLog.warning(PLog.Category.Ads) { "Consent form: ${error.message}" }
                afterConsent()
            }
        }, { error ->
            PLog.warning(PLog.Category.Ads) { "Consent info: ${error.message}" }
            afterConsent()
        })
    }

    private fun afterConsent() {
        _privacyOptionsRequired.value =
            consent.privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
        _canRequestAds.value = consent.canRequestAds()
        if (!_canRequestAds.value || started) return
        started = true
        MobileAds.initialize(context) {}
        preloadInterstitial()
    }

    /** "Ad privacy settings" in Profile (UMP privacy options form). */
    fun showPrivacyOptions(activity: Activity) {
        UserMessagingPlatform.showPrivacyOptionsForm(activity) { _canRequestAds.value = consent.canRequestAds() }
    }

    /** Whether a banner may show on this screen right now. */
    fun bannerAllowed(placement: String): Boolean = _canRequestAds.value && AdsGate.canShow(placement, adContext(history)).allowed

    private fun preloadInterstitial() {
        if (!_canRequestAds.value || Monetization.isPro) return
        if (interstitial != null && System.currentTimeMillis() - interstitialLoadedAt < 3_600_000) return
        InterstitialAd.load(context, config.interstitialUnitId, AdRequest.Builder().build(), object : InterstitialAdLoadCallback() {
            override fun onAdLoaded(ad: InterstitialAd) {
                ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                    override fun onAdDismissedFullScreenContent() = preloadInterstitial()
                    override fun onAdFailedToShowFullScreenContent(error: AdError) = preloadInterstitial()
                }
                interstitial = ad
                interstitialLoadedAt = System.currentTimeMillis()
            }

            override fun onAdFailedToLoad(error: LoadAdError) {
                PLog.info(PLog.Category.Ads) { "Interstitial not loaded: ${error.message}" }
            }
        })
    }

    /**
     * The user closed a battle's result screen. Counts the battle; shows an interstitial only when AdsGate allows (every
     * 2 battles and 15 min apart, 4 a day, after 5 sessions, never for Pro or near a wake flow — D-082).
     */
    fun battleClosed(activity: Activity?) {
        AppActivity.battleFinished()
        val ad = interstitial
        val allowed = AdsGate.canShow("battle_results_interstitial", adContext(history)).allowed
        if (!_canRequestAds.value || !allowed || ad == null || activity == null) {
            preloadInterstitial()
            return
        }
        interstitial = null
        history.record("battle_results_interstitial", System.currentTimeMillis())
        AppActivity.interstitialShown()
        ad.show(activity)
    }
}
