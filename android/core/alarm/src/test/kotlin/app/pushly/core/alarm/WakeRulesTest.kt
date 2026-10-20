package app.pushly.core.alarm

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Shared wake vectors — iOS WakeRulesTests and the server (supabase/tests/041_*) run the same files. */
class WakeRulesTest {
    @Serializable data class DecisionCase(
        val id: String,
        val mode: ChallengeMode,
        val t0: Long,
        val now: Long,
        val session: WakeRules.Session,
        val expected: WakeRules.Decision,
    )

    @Serializable data class DecisionFile(val cases: List<DecisionCase>)

    @Serializable data class PointsCase(
        val id: String,
        val finalTargetReps: Int,
        val mode: String,
        val snoozesUsed: Int,
        val avgQuality: Int,
        val expectedPoints: Int,
    )

    @Serializable data class PointsFile(val cases: List<PointsCase>)

    private val json = Json { ignoreUnknownKeys = true }

    private fun read(relative: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, relative).takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("not found: $relative")
    }

    @Test
    fun decisions() {
        val file = json.decodeFromString<DecisionFile>(read("shared/test-vectors/wake/decisions.json"))
        assertTrue(file.cases.size >= 20)
        for (c in file.cases) assertEquals(c.id, c.expected, WakeRules.decide(c.mode, c.t0, c.now, c.session))
    }

    @Test
    fun points() {
        val file = json.decodeFromString<PointsFile>(read("shared/test-vectors/wake/points.json"))
        for (c in file.cases) {
            assertEquals(c.id, c.expectedPoints, WakeRules.points(c.finalTargetReps, c.mode, c.snoozesUsed, c.avgQuality))
        }
    }
}
