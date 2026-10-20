package app.pushly.feature.wakeflow

import app.pushly.engine.rep.PoseFrame
import app.pushly.engine.rep.RepEngineInfo
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.roundToLong

/**
 * Debug-only pose recorder (roadmap P3-04, doc 05 §8): keeps the raw [PoseFrame]s of a session and exports them in
 * the shared vector format. `tools/pose-recorder/import.py` validates, gzips and adds them to shared/test-vectors.
 * Only landmarks — never video (CLAUDE.md §4.3). Same format as iOS PoseRecorder.
 */
class PoseRecorder {
    data class Label(
        val humanCount: Int,
        val placement: String = "side",
        val camera: String = "front",
        val tags: List<String> = emptyList(),
        val notes: String = "",
        val labeller: String = "",
    )

    private val frames = ArrayList<JsonObject>()
    private var width = 0
    private var height = 0
    private var startMs: Long? = null

    val frameCount: Int get() = frames.size

    fun append(f: PoseFrame, width: Int, height: Int) {
        if (frames.size >= MAX_FRAMES) return
        this.width = width
        this.height = height
        val t0 = startMs ?: f.tMs.also { startMs = it }
        frames += buildJsonObject {
            put("t", f.tMs - t0)
            put("lm", JsonArray(f.landmarks.map { p -> nums(p.x, p.y, p.z, p.visibility, p.presence) }))
            put("w", JsonArray(f.world.map { p -> nums(p.x, p.y, p.z) }))
            f.motion?.let { put("motion", r(it)) }
        }
    }

    private fun nums(vararg v: Double) = buildJsonArray { v.forEach { add(JsonPrimitive(r(it))) } }

    private fun r(v: Double): Double = (v * 100_000).roundToLong() / 100_000.0

    /** Vector JSON for [label]. */
    fun toJson(label: Label, device: String, now: Instant = Instant.now()): Pair<String, String> {
        val stamp = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC).format(now)
        val id = "real-${label.placement}-${label.humanCount}-$stamp"
        val json = buildJsonObject {
            put("id", id)
            put("specVersion", RepEngineInfo.SPEC_VERSION)
            putJsonObject("meta") {
                put("placement", label.placement)
                put("camera", label.camera)
                put("device", device)
                put("fps", 30)
                put("imageWidth", width)
                put("imageHeight", height)
                putJsonArray("tags") { label.tags.forEach { add(JsonPrimitive(it)) } }
                put("humanCount", label.humanCount)
                put("labeller", label.labeller)
                put("notes", label.notes)
            }
            put("frames", JsonArray(frames))
            putJsonObject("expected") {
                put("counted", if ("cheat" in label.tags) 0 else label.humanCount)
                put("toleranceCounted", if ("edge" in label.tags) 1 else 0)
            }
        }
        return id to json.toString()
    }

    /** Writes the vector into [dir] and returns the file (shared via FileProvider). */
    fun export(dir: File, label: Label, device: String): File {
        val (id, json) = toJson(label, device)
        dir.mkdirs()
        return File(dir, "$id.json").apply { writeText(json) }
    }

    companion object {
        const val MAX_FRAMES = 30 * 60 * 5 // 5 minutes
        val TAGS = listOf(
            "normal", "cheat", "half", "knees", "sag", "pike", "fast", "slow", "edge",
            "loose-clothing", "dim-light", "rear-camera", "two-people", "screen-replay",
        )
    }
}
