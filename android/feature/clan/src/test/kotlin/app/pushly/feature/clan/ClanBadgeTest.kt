package app.pushly.feature.clan

import app.pushly.core.designsystem.ClanBadgeStyle
import app.pushly.core.designsystem.Cosmetics
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Clan badges + the cosmetics catalog (D-074). Same checks as iOS ClanBadgeTests / CosmeticsTests. */
class ClanBadgeTest {
    private fun read(relative: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, relative).takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("not found: $relative")
    }

    @Test
    fun catalogMatchesTheSharedFile() {
        val c = Json.parseToJsonElement(read("shared/cosmetics/cosmetics.json")).jsonObject
        assertEquals(c["frames"]!!.jsonArray.map { it.jsonObject["id"]!!.jsonPrimitive.content }, Cosmetics.frames)
        val badge = c["clanBadge"]!!.jsonObject
        assertEquals(badge["shapes"]!!.jsonArray.map { it.jsonPrimitive.content }, Cosmetics.badgeShapes)
        assertEquals(badge["colors"]!!.jsonArray.map { it.jsonPrimitive.content }, Cosmetics.badgeColors)
        val emblems = badge["emblems"]!!.jsonArray.map { it.jsonObject }
        assertEquals(emblems.map { it["id"]!!.jsonPrimitive.content }, Cosmetics.emblems.map { it.id })
        assertEquals(emblems.map { it["glyph"]!!.jsonPrimitive.content }, Cosmetics.emblems.map { it.glyph })
        assertEquals(emblems.map { it["pro"]!!.jsonPrimitive.boolean }, Cosmetics.emblems.map { it.pro })
        Cosmetics.frames.forEach { assertTrue(it, Cosmetics.frameColors(it) != null) }
    }

    @Test
    fun emptyBadgeIsPickedFromTheTag() {
        // "ABC" = 65 + 66 + 67 = 198 → colour 198 % 8 = 6 (diamond), emblem free[(198 / 8) % 8 = 0] (flame). Same on iOS.
        val r = ClanBadgeStyle().resolved("abc")
        assertEquals("shield", r.shape)
        assertEquals("diamond", r.color)
        assertEquals("flame", r.emblem.id)
        val picked = ClanBadgeStyle("hex", "lime", "dragon").resolved("abc")
        assertEquals(listOf("hex", "lime", "dragon"), listOf(picked.shape, picked.color, picked.emblem.id))
        assertEquals("diamond", ClanBadgeStyle("star", "rainbow", "unicorn").resolved("abc").color)
        assertEquals(mapOf("shape" to "round", "color" to "gold", "emblem" to "crown"), ClanBadgeStyle("round", "gold", "crown").toMap())
    }

    @Test
    fun fixtureBadgeDecodes() {
        val home = ClanHome.decode(read("shared/contracts/fixtures/clan.json"))!!
        assertEquals(ClanBadgeStyle("shield", "flame", "wolf"), home.summary.badge)
        assertEquals(ClanBadgeStyle(), home.war?.rivals?.first()?.clan?.badge)
    }
}
