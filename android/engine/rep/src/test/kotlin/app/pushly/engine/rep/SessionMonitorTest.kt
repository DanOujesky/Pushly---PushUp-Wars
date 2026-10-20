package app.pushly.engine.rep

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Base64
import java.util.zip.GZIPInputStream
import java.util.zip.Inflater
import kotlin.math.abs
import kotlin.math.sin

/** Shared integrity vectors (doc 06 §2.3–2.4) — iOS SessionMonitorTests runs the same cases. */
class SessionMonitorTest {
    private data class Frame(val t: Long, var lm: List<List<Double>>, var w: List<List<Double>>, val motion: Double?)

    private fun repoFile(relative: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, relative).takeIf { it.exists() }?.let { return it }
            dir = dir.parentFile
        }
        error("not found: $relative")
    }

    /** Same transforms as tools/reference/build_vectors.py `integrity_transform`. */
    private fun apply(tr: JsonObject, input: List<Frame>): List<Frame> {
        var out = input.map { it.copy() }
        val every = tr["dropEveryMs"]?.jsonPrimitive?.longOrNull
        if (every != null) {
            val gap = tr["gapMs"]!!.jsonPrimitive.long
            val t0 = out.first().t
            out = out.filter { (it.t - t0) % every >= gap || it.t == t0 }
        }
        val k = tr["freezeAt"]?.jsonPrimitive?.intOrNull
        if (k != null) {
            val n = tr["freezeFrames"]!!.jsonPrimitive.int
            for (i in k + 1 until k + n) {
                out[i].lm = out[k].lm
                out[i].w = out[k].w
            }
        }
        val wobble = tr["wobble"]?.jsonPrimitive?.doubleOrNull
        if (wobble != null) {
            out.forEachIndexed { i, f ->
                val s = 1 + wobble * sin(i / 7.0)
                f.w = f.w.mapIndexed { j, p -> if (j in 13..16) p.map { it * s } else p }
            }
        }
        return out
    }

    @Test
    fun casesMatchTheReference() {
        val cases = Json.parseToJsonElement(repoFile("shared/test-vectors/integrity/cases.json").readText()).jsonObject["cases"]!!.jsonArray
        assertTrue(cases.size >= 5)
        for (c in cases.map { it.jsonObject }) {
            val id = c["id"]!!.jsonPrimitive.content
            val source = c["source"]!!.jsonPrimitive.content
            val v = Json.parseToJsonElement(
                GZIPInputStream(repoFile("shared/test-vectors/pushup/$source.json.gz").inputStream()).readBytes().decodeToString(),
            ).jsonObject
            val meta = v["meta"]!!.jsonObject
            val frames = apply(
                c["transform"]!!.jsonObject,
                v["frames"]!!.jsonArray.map { fr ->
                    val o = fr.jsonObject
                    Frame(
                        o["t"]!!.jsonPrimitive.long,
                        o["lm"]!!.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double } },
                        o["w"]!!.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double } },
                        o["motion"]?.jsonPrimitive?.doubleOrNull,
                    )
                },
            )
            val engine = RepEngine(meta["imageWidth"]!!.jsonPrimitive.double, meta["imageHeight"]!!.jsonPrimitive.double)
            val monitor = SessionMonitor()
            val t0 = frames.first().t
            for (f in frames) {
                val frame = PoseFrame(
                    f.t,
                    f.lm.map { PoseLandmark(it[0], it[1], it[2], it[3], it[4]) },
                    f.w.map { WorldPoint(it[0], it[1], it[2]) },
                    f.motion,
                )
                engine.process(frame)
                monitor.frame(frame, engine.lastFeatures, f.t - t0)
            }
            val exp = c["expected"]!!.jsonObject
            assertEquals("$id gaps", exp["gaps"]!!.jsonPrimitive.int, monitor.gaps)
            assertEquals("$id frozen", exp["frozen"]!!.jsonPrimitive.int, monitor.frozen)
            assertEquals("$id continuity", exp["continuity"]!!.jsonPrimitive.double, monitor.continuity, 0.002)
            assertEquals("$id replay", exp["replay"]!!.jsonPrimitive.double, monitor.replay, 0.002)
            val rows = exp["rows"]!!.jsonArray.map { r -> r.jsonArray.map { it.jsonPrimitive.long } }
            assertEquals("$id trace rows", rows.size, monitor.rows.size)
            rows.zip(monitor.rows).forEach { (ref, mine) ->
                assertEquals("$id row time", ref[0], mine[0])
                assertTrue("$id row ${ref[0]}", ref.indices.all { abs(ref[it] - mine[it]) <= 1 })
            }
        }
    }

    @Test
    fun traceRoundTrips() {
        val monitor = SessionMonitor()
        val lm = List(33) { PoseLandmark(0.5, 0.5, 0.0, 0.9, 0.9) }
        val world = List(33) { WorldPoint(it * 0.01, 0.0, 0.0) }
        val f = RepFeatures(0, true, 0.9, 91.4, 171.6, 175.0, 0.0, 5.0, 0.6, 100.0, 50.0, Placement.Side, null)
        monitor.frame(PoseFrame(1000, lm, world), f, 0)
        val packed = Base64.getDecoder().decode(monitor.encodedTrace())
        val inflater = Inflater(true)
        inflater.setInput(packed)
        val out = ByteArray(4096)
        val n = inflater.inflate(out)
        val json = Json.parseToJsonElement(out.copyOf(n).decodeToString()).jsonObject
        assertEquals(1, json["v"]!!.jsonPrimitive.int)
        assertEquals(listOf(listOf(0L, 91L, 172L, 90L, -1L)), json["rows"]!!.jsonArray.map { r -> r.jsonArray.map { it.jsonPrimitive.long } })
    }
}
