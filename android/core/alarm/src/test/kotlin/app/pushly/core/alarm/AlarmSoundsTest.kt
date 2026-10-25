package app.pushly.core.alarm

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pro sound pack (D-074) matches shared/cosmetics/cosmetics.json; unknown ids still fall back to the default. */
class AlarmSoundsTest {
    @Test
    fun soundsMatchTheSharedCatalog() {
        val sounds = Json.parseToJsonElement(RepoFile.read("shared/cosmetics/cosmetics.json")).jsonObject["alarmSounds"]!!.jsonArray
        assertEquals(sounds.map { it.jsonObject["id"]!!.jsonPrimitive.content }, AlarmSounds.bundled)
        assertEquals(
            sounds.filter { it.jsonObject["pro"]!!.jsonPrimitive.boolean }.map { it.jsonObject["id"]!!.jsonPrimitive.content }.toSet(),
            AlarmSounds.pro,
        )
    }

    @Test
    fun everySoundHasAFile() {
        AlarmSounds.bundled.forEach { id ->
            assertTrue(id, RepoFile.find("android/feature/alarm/src/main/res/raw/${AlarmSounds.resourceName(id)}.wav").exists())
        }
        assertEquals("pulse", AlarmSounds.resourceName("bundled.unknown"))
        assertEquals("thunder", AlarmSounds.resourceName("bundled.thunder"))
    }
}
