package app.pushly.feature.battle

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same vectors as iOS BattleRulesTests and the SQL test 081. */
class BattleRulesTest {
    @Serializable data class Case(
        val id: String,
        val mode: String,
        val variant: Map<String, Int>,
        val a: List<BattleRules.Rep>,
        val b: List<BattleRules.Rep>,
        val expected: BattleRules.Result,
    )

    @Serializable data class Vectors(val cases: List<Case>)

    private fun read(relative: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, relative).takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("not found: $relative")
    }

    @Test
    fun sharedVectors() {
        val v = Json { ignoreUnknownKeys = true }.decodeFromString(Vectors.serializer(), read("shared/test-vectors/battles/results.json"))
        assertTrue(v.cases.size >= 20)
        for (c in v.cases) assertEquals(c.id, c.expected, BattleRules.decide(c.mode, c.variant, c.a, c.b))
    }
}
