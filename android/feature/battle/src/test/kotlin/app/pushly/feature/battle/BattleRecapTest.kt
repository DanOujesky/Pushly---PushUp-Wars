package app.pushly.feature.battle

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same vectors as iOS BattleRecapTests (D-077). */
class BattleRecapTest {
    @Serializable data class Margin(
        val kind: String,
        val n: Int? = null,
        val ms: Long? = null,
        val mine: Int? = null,
        val theirs: Int? = null,
        val byMe: Boolean? = null,
    )
    @Serializable data class Expected(val outcome: String, val mine: Int, val theirs: Int, val margin: Margin, val close: Boolean)
    @Serializable data class Case(val id: String, val battle: Battle, val expected: Expected)
    @Serializable data class Vectors(val cases: List<Case>)

    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    private fun read(relative: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, relative).takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("not found: $relative")
    }

    private fun margin(m: Margin): BattleRecap.Margin? = when (m.kind) {
        "reps" -> m.n?.let { BattleRecap.Margin.Reps(it) }
        "time" -> m.ms?.let { BattleRecap.Margin.Time(it) }
        "rounds" -> BattleRecap.Margin.Rounds(m.mine ?: 0, m.theirs ?: 0)
        "form" -> BattleRecap.Margin.Form
        "forfeit" -> BattleRecap.Margin.Forfeit(m.byMe ?: false)
        "turnMissed" -> BattleRecap.Margin.TurnMissed(m.byMe ?: false)
        "draw" -> BattleRecap.Margin.Draw
        "void" -> BattleRecap.Margin.Void
        else -> null
    }

    private fun vectors() = json.decodeFromString(Vectors.serializer(), read("shared/test-vectors/battles/recap.json"))

    @Test
    fun sharedVectors() {
        val v = vectors()
        assertTrue(v.cases.size >= 10)
        v.cases.forEach { c ->
            val r = BattleRecap.of(c.battle)
            assertEquals(c.id, c.expected.outcome, r.outcome.name.lowercase())
            assertEquals(c.id, c.expected.mine, r.mine)
            assertEquals(c.id, c.expected.theirs, r.theirs)
            assertEquals(c.id, margin(c.expected.margin), r.margin)
            assertEquals(c.id, c.expected.close, r.isClose)
        }
    }

    @Test
    fun summaryCountsCloseCallsAndTrophies() {
        val s = HistorySummary.of(vectors().cases.map { it.battle })
        assertEquals(2, s.closeLosses)
        assertEquals(3, s.clutchWins)
        assertEquals(2, s.trophyNet)
        assertEquals(10, s.form.size)
        assertEquals(BattleRecap.Outcome.Loss, s.form.first())
    }
}
