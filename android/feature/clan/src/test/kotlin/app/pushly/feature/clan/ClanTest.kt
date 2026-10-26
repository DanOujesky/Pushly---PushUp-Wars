package app.pushly.feature.clan

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same cases as iOS ClanFeatureTests. */
class ClanTest {
    private fun fixture(name: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, "shared/contracts/fixtures/$name").takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("fixture not found: $name")
    }

    /** Clan Wars v2 (D-078) — same expectations as iOS ClanWarStateTests. */
    @Test
    fun warStateDecodesAndSummarises() {
        val state = ClanWarState.decode(fixture("clan_war_state.json")) ?: error("no state")
        val war = state.current ?: error("no current war")
        assertTrue(war.isLive)
        assertEquals(35, war.gap)
        assertEquals(1, war.myRank)
        assertEquals(2, war.rivals.size)
        assertTrue(war.mine?.stakes != null)
        assertFalse(war.feed.first().mine)
        assertTrue(war.rally?.available == true)
        val last = state.last ?: error("no last war")
        assertTrue(last.isFinished)
        assertEquals(30, last.result?.ratingDelta)
        assertEquals(30, last.clans.first().ratingDelta)
        assertNull(ClanWarState.decode("null"))
    }

    @Test
    fun clock() {
        assertEquals(Triple(2, 4, 0), WarClock.until("1970-01-03T04:00:00Z", 0))
        assertEquals(Triple(0, 3, 12), WarClock.until("1970-01-01T03:12:00Z", 0))
        assertNull(WarClock.until("1969-12-31T00:00:00Z", 0))
    }

    @Test
    fun decodesFixtures() {
        val home = ClanHome.decode(fixture("clan.json"))
        assertEquals("IRONW", home?.summary?.tag)
        assertEquals("leader", home?.summary?.myRole)
        assertEquals(true, home?.war?.isLive)
        assertEquals(listOf("IRONW", "NIGHT", "REDFO"), home?.war?.clans?.map { it.clan.tag })
        assertEquals(1, home?.warState?.last?.result?.rank)
        assertTrue((home?.members?.size ?: 0) >= 2)
        assertNull(ClanHome.decode("null"))
        assertEquals("system", ClanMessage.decodeList(fixture("clan_messages.json")).first().kind)
        assertTrue(ClanSummary.decodeList(fixture("clan_search.json")).isNotEmpty())
    }

    @Test
    fun permissionsMatchTheServer() {
        assertEquals(listOf(ClanRole.CoLeader, ClanRole.Elder), ClanRole.Leader.assignable(ClanRole.Member))
        assertEquals(listOf(ClanRole.Elder), ClanRole.CoLeader.assignable(ClanRole.Member))
        assertTrue(ClanRole.CoLeader.assignable(ClanRole.CoLeader).isEmpty())
        assertTrue(ClanRole.Elder.assignable(ClanRole.Member).isEmpty())
        assertTrue(ClanRole.Elder.canKick(ClanRole.Member))
        assertFalse(ClanRole.Elder.canKick(ClanRole.Elder))
        assertFalse(ClanRole.CoLeader.canKick(ClanRole.Leader))
        assertFalse(ClanRole.Member.canKick(ClanRole.Member))
    }

    @Test
    fun friendlyErrors() {
        assertEquals(ClanViewModel.Notice.Taken, ClanViewModel.noticeFor(IllegalStateException("hint: taken")))
        assertEquals(ClanViewModel.Notice.RateLimited, ClanViewModel.noticeFor(IllegalStateException("rate limited")))
    }

    @Test
    fun warHistoryAndChests() {
        val wars = ClanWarResult.decodeList(fixture("clan_war_results.json"))
        assertEquals(1, wars.first().rank)
        assertEquals(3, wars.first().of)
        assertEquals(3, wars.first().clans.size)
        assertEquals("W", wars.first().letter)
        val chests = WarChests.decode(fixture("war_chests.json"))
        assertEquals(250, chests.unopened.first().xp)
        assertEquals(3, chests.medals.gold)
    }

    @Test
    fun streak() {
        fun war(rank: Int, of: Int = 3) = ClanWarResult("x", "2026-10-12", rank, of, 1, 0)
        assertEquals("W" to 2, WarStreak.current(listOf(war(1), war(1), war(2))))
        assertEquals("L", WarStreak.current(listOf(war(3), war(1)))?.first)
        assertEquals("L", WarStreak.current(listOf(war(1, of = 1)))?.first)    // alone is not a win
        assertNull(WarStreak.current(emptyList()))
    }
}

class ChatLayoutTest {
    private fun msg(id: Long, user: String?, at: String, kind: String = "text") =
        ClanMessage(id, kind, "x", user?.let { ClanMessage.Author(it, it) }, at)

    @org.junit.Test
    fun groupsConsecutiveMessagesBySameAuthor() {
        val a = msg(1, "u1", "2026-10-21T10:00:00Z")
        val b = msg(2, "u1", "2026-10-21T10:03:20Z")
        val c = msg(3, "u2", "2026-10-21T10:04:00Z")
        val d = msg(4, "u2", "2026-10-21T10:20:00Z")
        org.junit.Assert.assertTrue(ChatLayout.startsGroup(a, null))
        org.junit.Assert.assertFalse(ChatLayout.startsGroup(b, a))
        org.junit.Assert.assertTrue(ChatLayout.startsGroup(c, b))
        org.junit.Assert.assertTrue(ChatLayout.startsGroup(d, c))
        org.junit.Assert.assertTrue(ChatLayout.startsGroup(msg(5, null, "2026-10-21T10:21:00Z", "system"), d))
    }

    @org.junit.Test
    fun daySeparatorOnNewDay() {
        val utc = java.time.ZoneOffset.UTC
        val a = msg(1, "u1", "2026-10-21T23:59:00Z")
        val b = msg(2, "u1", "2026-10-22T00:01:00Z")
        org.junit.Assert.assertTrue(ChatLayout.newDay(a, null, utc))
        org.junit.Assert.assertTrue(ChatLayout.newDay(b, a, utc))
        org.junit.Assert.assertFalse(ChatLayout.newDay(a, a, utc))
    }

    @org.junit.Test
    fun parsesPostgresTimestamps() {
        org.junit.Assert.assertNotNull(ChatLayout.instant("2026-10-21T10:03:20.123456+00:00"))
        org.junit.Assert.assertNotNull(ChatLayout.instant("2026-10-21T10:03:20Z"))
    }
}
