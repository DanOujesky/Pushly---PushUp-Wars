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
}
