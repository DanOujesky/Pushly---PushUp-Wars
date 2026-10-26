package app.pushly

import app.pushly.core.common.DeepLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Same cases as iOS AppRouterTests. */
class AppRouterTest {
    @Test
    fun pagesStackAndPop() {
        val router = AppRouter()
        router.push(app.pushly.core.designsystem.ProfileTarget.User("u1"))
        router.push(app.pushly.core.designsystem.ProfileTarget.Clan("c1"))
        assertEquals(2, router.pages.value.size)
        router.pop()
        assertEquals(listOf(app.pushly.core.designsystem.ProfileTarget.User("u1")), router.pages.value)
        router.openProfile(null)
        assertEquals(0, router.pages.value.size)
    }

    @Test
    fun deepLinksSelectTheRightTab() {
        val router = AppRouter()
        router.handle("pushly://battle/invite/AB12")
        assertEquals(AppTab.Battle, router.selectedTab.value)
        assertEquals(DeepLink.BattleInvite("AB12"), router.consumePendingLink())
        assertNull(router.consumePendingLink())

        router.handle("https://pushly.app/u/AnaFit")
        assertEquals("a profile link opens over the current tab", AppTab.Battle, router.selectedTab.value)
        assertEquals(listOf(app.pushly.core.designsystem.ProfileTarget.Username("AnaFit")), router.pages.value)
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
