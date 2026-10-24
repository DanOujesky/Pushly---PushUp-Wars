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

    /** Clan Wars with more fight (D-068) — same expectations as iOS ClanWarActionTests. */
    @Test
    fun warExtrasDecodeAndSummarise() {
        val war = ClanHome.decode(fixture("clan.json"))?.war ?: error("no war")
        assertEquals(30, war.gap)
        assertEquals(7, war.days.size)
        assertEquals(1 to 1, war.daysWon)
        assertEquals("us", war.feed.first().side)
        assertEquals(250, war.theirTop.first().reps)
        assertTrue(war.rally?.available == true)
    }

    @Test
    fun decodesFixtures() {
        val home = ClanHome.decode(fixture("clan.json"))
        assertEquals("IRON", home?.summary?.tag)
        assertEquals("co_leader", home?.summary?.myRole)
        assertEquals(280, home?.war?.score?.us)
        assertEquals("OWL", home?.war?.opponent?.tag)
        assertTrue((home?.members?.size ?: 0) >= 5)
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
        val wars = ClanWarRecord.decodeList(fixture("clan_war_history.json"))
        assertEquals("OWL", wars.first().opponent?.tag)
        assertNull(wars.last().opponent)
        val chests = WarChests.decode(fixture("war_chests.json"))
        assertEquals(250, chests.unopened.first().xp)
        assertEquals(3, chests.medals.gold)
    }

    @Test
    fun streak() {
        fun war(won: Boolean?, draw: Boolean = false) = ClanWarRecord("x", "2026-10-12", null, 1, 0, won, draw, "score")
        assertEquals("W" to 2, WarStreak.current(listOf(war(true), war(true), war(false))))
        assertEquals("L", WarStreak.current(listOf(war(false), war(true)))?.first)
        assertNull(WarStreak.current(listOf(war(null, draw = true), war(true))))
        assertNull(WarStreak.current(emptyList()))
    }
}
