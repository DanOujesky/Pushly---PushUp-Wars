package app.pushly.engine.rep

import app.pushly.engine.rep.generated.PushupSpecV1
import java.util.Base64
import java.util.zip.Deflater
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * On-device session integrity signals (doc 06 §2.3–2.4) and the 10 Hz feature trace for the rep log.
 * Port of tools/reference/pushly_ref/integrity.py; shared vectors shared/test-vectors/integrity (same as iOS).
 * Feed every frame after [RepEngine.process] with its time since the session start.
 */
class SessionMonitor {
    val rows = ArrayList<LongArray>()
    var gaps = 0
        private set
    var frozen = 0
        private set
    private var lastSample: Long? = null
    private var lastFrameT: Long? = null
    private var firstT: Long? = null
    private var prevXY: DoubleArray? = null
    private var same = 0
    private val limbs = linkedMapOf<String, ArrayList<Double>>(
        "upperArm" to ArrayList(), "forearm" to ArrayList(), "thigh" to ArrayList(), "shin" to ArrayList(),
    )

    fun frame(frame: PoseFrame, features: RepFeatures?, relativeMs: Long) {
        val t = frame.tMs
        if (firstT == null) firstT = t
        lastFrameT?.let { if (t - it > GAP_MS) gaps++ }
        lastFrameT = t
        val xy = DoubleArray(frame.landmarks.size * 2) { i -> frame.landmarks[i / 2].let { if (i % 2 == 0) it.x else it.y } }
        val prev = prevXY
        if (prev != null && prev.contentEquals(xy)) {
            same++
            if (same == FROZEN_FRAMES - 1) frozen++
        } else {
            same = 0
        }
        prevXY = xy
        if (features == null || frame.landmarks.size != 33 || frame.world.size != 33) return
        val idx = if (features.leftSide) LEFT else RIGHT
        val req = PushupSpecV1.Visibility.REQUIRED_LANDMARK_MIN
        val pairs = listOf("upperArm" to (idx[0] to idx[1]), "forearm" to (idx[1] to idx[2]), "thigh" to (idx[3] to idx[4]), "shin" to (idx[4] to idx[5]))
        for ((name, ab) in pairs) {
            val (a, b) = ab
            if (frame.landmarks[a].visibility >= req && frame.landmarks[b].visibility >= req) {
                val p = frame.world[a]
                val q = frame.world[b]
                limbs.getValue(name) += sqrt((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y) + (p.z - q.z) * (p.z - q.z))
            }
        }
        val last = lastSample
        if (last == null || relativeMs - last >= TRACE_INTERVAL_MS) {
            lastSample = relativeMs
            rows += longArrayOf(
                relativeMs, rnd(features.elbow), rnd(features.bodyLine), rnd(features.visibility * 100),
                features.motion?.let { rnd(it * 1000) } ?: -1,
            )
        }
    }

    /** 0–1: camera feed gaps (> 400 ms) above 3 per minute, or a frozen feed → 1. */
    val continuity: Double
        get() {
            if (frozen > 0) return 1.0
            val span = ((lastFrameT ?: 0) - (firstT ?: 0)).toDouble()
            val rate = gaps / max(span / 60_000.0, 1.0)
            return score((rate - GAPS_PER_MINUTE_OK) / GAPS_PER_MINUTE_OK)
        }

    /** 0–1: how much the world-landmark limb lengths wobble (flat replay on a screen). */
    val replay: Double
        get() {
            var worst = 0.0
            for (values in limbs.values) {
                if (values.size < LIMB_MIN_SAMPLES) continue
                val v = values.sorted()
                val n = v.size
                val p10 = v[(0.1 * (n - 1)).toInt()]
                val p50 = v[(0.5 * (n - 1)).toInt()]
                val p90 = v[(0.9 * (n - 1)).toInt()]
                if (p50 > 1e-6) worst = max(worst, (p90 - p10) / p50)
            }
            return score((worst - LIMB_SPREAD_OK) / LIMB_SPREAD_RANGE)
        }

    /** The trace for the rep log: JSON, raw deflate, base64 (decoded by the server, doc 06 §4). */
    fun encodedTrace(): String {
        val body = rows.joinToString(",") { r -> r.joinToString(",", "[", "]") }
        val json = "{\"v\":1,\"fields\":[\"t\",\"elbow\",\"bodyLine\",\"vis\",\"motion\"],\"rows\":[$body]}".encodeToByteArray()
        val deflater = Deflater(6, true)
        deflater.setInput(json)
        deflater.finish()
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(4096)
        while (!deflater.finished()) out.write(buf, 0, deflater.deflate(buf))
        deflater.end()
        return Base64.getEncoder().encodeToString(out.toByteArray())
    }

    companion object {
        const val TRACE_INTERVAL_MS = 100L
        private const val GAP_MS = 400L
        private const val GAPS_PER_MINUTE_OK = 3.0
        private const val FROZEN_FRAMES = 5
        private const val LIMB_SPREAD_OK = 0.15
        private const val LIMB_SPREAD_RANGE = 0.35
        private const val LIMB_MIN_SAMPLES = 30
        private val LEFT = intArrayOf(11, 13, 15, 23, 25, 27)
        private val RIGHT = intArrayOf(12, 14, 16, 24, 26, 28)

        fun rnd(x: Double): Long = floor(x + 0.5).toLong()

        fun score(x: Double): Double = floor(min(1.0, max(0.0, x)) * 1000 + 0.5) / 1000
    }
}
