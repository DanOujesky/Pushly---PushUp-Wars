package app.pushly.feature.shop

import app.pushly.core.common.AdsGate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ads + Pushly Pro wiring (D-073): config fallbacks and the ad history behind the caps. Same as iOS ShopFeatureTests. */
class ShopTest {
    @Test
    fun configFallsBackToGoogleTestIds() {
        val c = ShopConfig.of("", " ", "")
        assertEquals(ShopConfig.TEST_BANNER, c.bannerUnitId)
        assertTrue(c.usesTestAds)
        assertFalse(c.purchasesAvailable)
    }

    @Test
    fun configUsesRealValues() {
        val c = ShopConfig.of("ca-app-pub-123/456", "ca-app-pub-123/789", "goog_abc")
        assertFalse(c.usesTestAds)
        assertTrue(c.purchasesAvailable)
    }

    @Test
    fun historyKeepsOneWeekForTheCaps() {
        var stored: String? = null
        val h = AdHistory({ stored }, { stored = it })
        val day = 24L * 3600 * 1000
        h.record("battle_results_interstitial", 0)
        h.record("battle_results_interstitial", 8 * day)
        assertEquals(listOf(8 * day), h.shown.map { it.atMs })
    }

    @Test
    fun interstitialFollowsAdsGate() {
        val ctx = AdsGate.Context(completedSessions = 5, nowMs = 10_000_000, battlesSinceInterstitial = 3)
        assertTrue(AdsGate.canShow("battle_results_interstitial", ctx).allowed)
        assertEquals("pro", AdsGate.canShow("battle_results_interstitial", ctx.copy(isPro = true)).reason)
    }
}
