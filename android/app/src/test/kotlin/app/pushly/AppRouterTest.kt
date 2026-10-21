package app.pushly

import app.pushly.core.common.DeepLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Same cases as iOS AppRouterTests. */
class AppRouterTest {
    @Test
    fun deepLinksSelectTheRightTab() {
        val router = AppRouter()
        router.handle("pushly://battle/invite/AB12")
        assertEquals(AppTab.Battle, router.selectedTab.value)
        assertEquals(DeepLink.BattleInvite("AB12"), router.consumePendingLink())
        assertNull(router.consumePendingLink())

        router.handle("https://pushly.app/u/AnaFit")
        assertEquals("a profile link opens over the current tab", AppTab.Battle, router.selectedTab.value)
        assertEquals(AppRouter.ProfileKey(username = "AnaFit"), router.profile.value)
    }

    @Test
    fun unknownLinksAreIgnored() {
        val router = AppRouter()
        router.select(AppTab.Clan)
        router.handle("pushly://nonsense")
        assertEquals(AppTab.Clan, router.selectedTab.value)
        assertNull(router.consumePendingLink())
    }
}
