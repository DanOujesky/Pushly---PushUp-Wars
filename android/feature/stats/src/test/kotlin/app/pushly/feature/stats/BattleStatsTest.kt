package app.pushly.feature.stats

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Trophy-first stats (D-067) — same expectations as iOS BattleStatsTests. */
class BattleStatsTest {
    private fun fixture(): BattleStats {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val f = File(dir, "shared/contracts/fixtures/battle_stats.json")
            if (f.exists()) return BattleStats.decode(f.readText())
            dir = dir.parentFile
        }
        error("fixture not found")
    }

    @Test
    fun decodesTheContractFixture() {
        val s = fixture()
        assertEquals(1340, s.trophies)
        assertEquals("gold", s.league)
        assertEquals(1466, s.next?.at)
        assertEquals(12, s.targets.first().gap)
        assertEquals(2, s.recent.size)
    }

    @Test
    fun progressAndWinRate() {
        val s = fixture()
        assertTrue(kotlin.math.abs(s.progressToNext - 140.0 / 266.0) < 0.0001)
        assertEquals(61, s.record.winRate)
    }
}
