package app.pushly.core.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/** Same cases as iOS DeepLinkTests — keep them in sync (CLAUDE.md §4.1). */
class DeepLinkTest {
    private val id = "a0000000-0000-4000-8000-000000000001"
    private val uuid = UUID.fromString(id)

    @Test
    fun customSchemeLinks() {
        assertEquals(DeepLink.Wake, DeepLink.parse("pushly://wake"))
        assertEquals(DeepLink.Pro, DeepLink.parse("pushly://pro"))
        assertEquals(DeepLink.Alarm(uuid), DeepLink.parse("pushly://alarm/$id"))
        assertEquals(DeepLink.BattleInvite("AB12CD"), DeepLink.parse("pushly://battle/invite/AB12CD"))
        assertEquals(DeepLink.ClanWar(uuid), DeepLink.parse("pushly://clan/war/$id"))
        assertEquals(DeepLink.AlarmHealth, DeepLink.parse("pushly://settings/alarm-health"))
        assertEquals(DeepLink.Leaderboard("wake"), DeepLink.parse("pushly://leaderboard/wake"))
    }

    @Test
    fun universalLinks() {
        assertEquals(DeepLink.User("AnaFit"), DeepLink.parse("https://pushly.app/u/AnaFit"))
        assertEquals(DeepLink.BattleInvite("XY99"), DeepLink.parse("https://pushly.app/b/XY99"))
        assertEquals(DeepLink.Battle(uuid), DeepLink.parse("https://pushly.app/battle/$id"))
    }

    @Test
    fun rejectsUnknownOrMalformed() {
        assertNull(DeepLink.parse("https://evil.example/u/AnaFit"))
        assertNull(DeepLink.parse("pushly://alarm/not-a-uuid"))
        assertNull(DeepLink.parse("pushly://u/a"))
        assertNull(DeepLink.parse("pushly://leaderboard/secret"))
        assertNull(DeepLink.parse("pushly://battle/invite/../../x"))
        assertNull(DeepLink.parse("http://pushly.app/wake"))
        assertNull(DeepLink.parse("not a url"))
    }

    @Test
    fun retryableDefaults() {
        assertTrue(AppError(AppErrorCode.RateLimited, "").retryable)
        assertTrue(AppError(AppErrorCode.Network, "").retryable)
        assertFalse(AppError(AppErrorCode.IntegrityFailed, "").retryable)
        assertEquals(AppErrorCode.Unknown, AppErrorCode.fromWire("SOMETHING_NEW"))
    }

    @Test
    fun fixedClock() {
        val c = FixedClock(now = 1_000, monotonic = 5)
        c.advance(250)
        assertEquals(1_250, c.nowMs())
        assertEquals(255, c.monotonicMs())
    }
}
