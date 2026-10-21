package app.pushly.feature.battle

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same vectors as iOS BattleHudTests. */
class BattleHudTest {
    @Serializable data class Clock(val id: String, val t: Long, val expected: BattleHud.Bo3Clock)
    @Serializable data class Clinched(val id: String, val mySets: List<Int>, val theirRaw: List<Int>, val expected: Boolean)
    @Serializable data class Turn(val id: String, val t: Long, val myLast: Long?, val theirLast: Long?, val expected: BattleHud.TurnState)
    @Serializable data class Vectors(val bo3Clock: List<Clock>, val bo3Clinched: List<Clinched>, val turns: List<Turn>)

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
        val v = Json.decodeFromString(Vectors.serializer(), read("shared/test-vectors/battles/hud.json"))
        assertTrue(v.bo3Clock.isNotEmpty() && v.bo3Clinched.isNotEmpty() && v.turns.isNotEmpty())
        v.bo3Clock.forEach { assertEquals(it.id, it.expected, BattleHud.bo3Clock(it.t)) }
        v.bo3Clinched.forEach { assertEquals(it.id, it.expected, BattleHud.bo3Clinched(it.mySets, it.theirRaw)) }
        v.turns.forEach { assertEquals(it.id, it.expected, BattleHud.turnState(it.t, it.myLast, it.theirLast)) }
    }

    @Test
    fun setsStopAtAPause() {
        val reps = listOf(BattleRules.Rep(1000, 80, 0), BattleRules.Rep(2500, 80, 0), BattleRules.Rep(6000, 80, 0), BattleRules.Rep(136_000, 80, 1))
        assertEquals(listOf(2, 1, 0), BattleHud.mySets(reps))
    }
}
