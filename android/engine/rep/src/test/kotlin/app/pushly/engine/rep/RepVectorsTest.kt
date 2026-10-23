package app.pushly.engine.rep

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.zip.GZIPInputStream
import kotlin.math.abs

private fun repoDir(relative: String): File {
    var dir: File? = File("").absoluteFile
    while (dir != null) {
        val candidate = File(dir, relative)
        if (candidate.exists()) return candidate
        dir = dir.parentFile
    }
    error("Not found: $relative")
}

/**
 * Runs every shared push-up vector (iOS RepVectorTests runs the same files — CLAUDE.md §4.1). The engine must match
 * the human label and reproduce the reference engine's events exactly (quality ±1).
 */
class RepVectorsTest {
    @Test
    fun allVectorsMatchLabelsAndReference() {
        val files = repoDir("shared/test-vectors/pushup").listFiles { f -> f.name.endsWith(".json.gz") }.orEmpty().sortedBy { it.name }
        assertTrue("expected ≥ 25 vectors, found ${files.size}", files.size >= 25)
        for (file in files) {
            val v = Json.parseToJsonElement(GZIPInputStream(file.inputStream()).readBytes().decodeToString()).jsonObject
            val id = v["id"]!!.jsonPrimitive.content
            val meta = v["meta"]!!.jsonObject
            val engine = RepEngine(meta["imageWidth"]!!.jsonPrimitive.double, meta["imageHeight"]!!.jsonPrimitive.double)
            val events = ArrayList<RepEvent>()
            for (fr in v["frames"]!!.jsonArray) {
                val o = fr.jsonObject
                val lm = o["lm"]!!.jsonArray.map { p ->
                    val a = p.jsonArray.map { it.jsonPrimitive.double }
                    PoseLandmark(a[0], a[1], a[2], a[3], a[4])
                }
                val w = o["w"]!!.jsonArray.map { p ->
                    val a = p.jsonArray.map { it.jsonPrimitive.double }
                    WorldPoint(a[0], a[1], a[2])
                }
                events += engine.process(PoseFrame(o["t"]!!.jsonPrimitive.long, lm, w, o["motion"]?.jsonPrimitive?.doubleOrNull))
            }
            val rejected = events.filterIsInstance<RepEvent.Rejected>().groupingBy { it.reason.code }.eachCount()
            val expected = v["expected"]!!.jsonObject
            // Real recordings may carry a tolerance; a tracked "knownGap" (tools/pose-recorder/import.py) checks parity only.
            if (expected["knownGap"] == null) {
                val tolerance = expected["toleranceCounted"]?.jsonPrimitive?.int ?: 0
                val want = expected["counted"]!!.jsonPrimitive.int
                assertTrue("$id: counted ${engine.counted} vs $want ±$tolerance", abs(engine.counted - want) <= tolerance)
            }
            (expected["rejected"] as? JsonObject)?.let { exp ->
                assertEquals("$id: rejected", exp.mapValues { it.value.jsonPrimitive.int }, rejected)
            }
            val tags = meta["tags"]!!.jsonArray.map { it.jsonPrimitive.content }
            if ("cheat" in tags && expected["knownGap"] == null) assertEquals("$id: cheat must count 0", 0, engine.counted)

            val ref = v["reference"]!!.jsonObject["events"]!!.jsonArray.map { it.jsonObject }
            assertEquals("$id: event count", ref.size, events.size)
            events.zip(ref).forEach { (mine, r) ->
                val type = r["type"]!!.jsonPrimitive.content
                val t = r["t"]!!.jsonPrimitive.long
                when (mine) {
                    is RepEvent.Counted -> {
                        assertEquals("$id: type", "counted", type)
                        assertEquals("$id: index", r["index"]!!.jsonPrimitive.int, mine.rep.index)
                        assertEquals("$id: t", t, mine.rep.tEnd)
                        val q = r["quality"]!!.jsonPrimitive.intOrNull ?: -99
                        assertTrue("$id: quality ${mine.rep.quality} vs $q", abs(q - mine.rep.quality) <= 1)
                    }
                    is RepEvent.Rejected -> {
                        assertEquals("$id: type", "rejected", type)
                        assertEquals("$id: reason", r["reason"]!!.jsonPrimitive.contentOrNull, mine.reason.code)
                        assertEquals("$id: t", t, mine.t)
                    }
                }
            }
        }
    }

    /** D-064: battles pass allowFront = false — a front set never starts; normally front reps are marked `front`. */
    @Test
    fun frontPlacementCanBeDisabled() {
        val file = repoDir("shared/test-vectors/pushup/real-front-8-2026-10-22T211114Z.json.gz")
        val v = Json.parseToJsonElement(GZIPInputStream(file.inputStream()).readBytes().decodeToString()).jsonObject
        val meta = v["meta"]!!.jsonObject
        val w = meta["imageWidth"]!!.jsonPrimitive.double
        val h = meta["imageHeight"]!!.jsonPrimitive.double
        val open = RepEngine(w, h)
        val battle = RepEngine(w, h, allowFront = false)
        val fronts = ArrayList<Boolean>()
        for (fr in v["frames"]!!.jsonArray) {
            val o = fr.jsonObject
            val lm = o["lm"]!!.jsonArray.map { p ->
                val a = p.jsonArray.map { it.jsonPrimitive.double }
                PoseLandmark(a[0], a[1], a[2], a[3], a[4])
            }
            val wp = o["w"]!!.jsonArray.map { p ->
                val a = p.jsonArray.map { it.jsonPrimitive.double }
                WorldPoint(a[0], a[1], a[2])
            }
            val frame = PoseFrame(o["t"]!!.jsonPrimitive.long, lm, wp)
            open.process(frame).filterIsInstance<RepEvent.Counted>().forEach { fronts += it.rep.front }
            battle.process(frame)
        }
        assertEquals(8, fronts.size)
        assertTrue(fronts.all { it })
        assertEquals(0, battle.counted)
    }

    @Test
    fun reversalsIgnoreSmallWiggles() {
        assertEquals(1, RepMath.reversals(listOf(150.0, 120.0, 90.0, 95.0, 120.0, 160.0), 8.0))
        assertEquals(1, RepMath.reversals(listOf(150.0, 120.0, 125.0, 100.0, 160.0), 8.0))
        assertEquals(3, RepMath.reversals(listOf(150.0, 110.0, 135.0, 85.0, 160.0), 8.0))
    }
}
