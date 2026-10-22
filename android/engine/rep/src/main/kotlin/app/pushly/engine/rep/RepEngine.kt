package app.pushly.engine.rep

import app.pushly.engine.rep.generated.PushupSpecV2
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** One normalised image landmark (MediaPipe): un-mirrored, upright image, y down. */
data class PoseLandmark(val x: Double, val y: Double, val z: Double, val visibility: Double, val presence: Double)

/** One world landmark in metres (hip-centred, y down). */
data class WorldPoint(val x: Double, val y: Double, val z: Double)

/** One analysed camera frame (doc 05 §3). [motion] = device motion RMS in g (anti-cheat, doc 06 §2.1). */
data class PoseFrame(val tMs: Long, val landmarks: List<PoseLandmark>, val world: List<WorldPoint>, val motion: Double? = null)

enum class RepState { NotReady, Top, Descending, Bottom, Ascending, Recover }

enum class Placement { Side, Front, Unknown }

/** Why a rep did not count (doc 05 §5). [code] is the wire value used in rep logs and test vectors. */
enum class RejectReason(val code: String) {
    NotDeepEnough("NOT_DEEP_ENOUGH"),
    NoLockout("NO_LOCKOUT"),
    HipsSagging("HIPS_SAGGING"),
    HipsPiked("HIPS_PIKED"),
    KneesDown("KNEES_DOWN"),
    BodyNotVisible("BODY_NOT_VISIBLE"),
    TooFast("TOO_FAST"),
    TooSlow("TOO_SLOW"),
    IrregularMotion("IRREGULAR_MOTION"),
    Integrity("INTEGRITY"),
}

data class CountedRep(
    val index: Int,
    val quality: Int,
    val tStart: Long,
    val tBottom: Long,
    val tEnd: Long,
    val minElbow: Double,
    val maxElbow: Double,
    val minBodyLine: Double,
    val depth: Double,
)

sealed interface RepEvent {
    data class Counted(val rep: CountedRep) : RepEvent
    data class Rejected(val reason: RejectReason, val t: Long) : RepEvent
}

/** Per-frame features (doc 05 §4). */
data class RepFeatures(
    val t: Long,
    val leftSide: Boolean,
    val visibility: Double,
    val elbow: Double,
    val bodyLine: Double,
    val knee: Double,
    /** Pixels; > 0 = hip below the shoulder–ankle line (sagging). */
    val hipDeviation: Double,
    val torsoTilt: Double,
    val bbox: Double,
    val shoulderY: Double,
    val upperArm: Double,
    val placement: Placement,
    val motion: Double?,
    /** How elbow / visibility / plank were measured (Side or Front), locked while a set runs (spec v2). */
    val mode: Placement = Placement.Side,
    /** Pixels: mean wrist y − mean shoulder y (front plank: hands on the floor below the shoulders). */
    val wristDrop: Double = 0.0,
)

internal object RepMath {
    fun angle(a: DoubleArray, b: DoubleArray, c: DoubleArray): Double {
        val ba = DoubleArray(a.size) { a[it] - b[it] }
        val bc = DoubleArray(c.size) { c[it] - b[it] }
        val na = sqrt(ba.sumOf { it * it })
        val nc = sqrt(bc.sumOf { it * it })
        if (na < 1e-9 || nc < 1e-9) return 180.0
        var dot = 0.0
        for (i in ba.indices) dot += ba[i] * bc[i]
        val cosine = max(-1.0, min(1.0, dot / (na * nc)))
        return Math.toDegrees(acos(cosine))
    }

    fun dist(a: DoubleArray, b: DoubleArray): Double {
        var s = 0.0
        for (i in a.indices) s += (a[i] - b[i]) * (a[i] - b[i])
        return sqrt(s)
    }

    fun clamp01(v: Double): Double = max(0.0, min(1.0, v))

    fun median(values: List<Double>): Double {
        val s = values.sorted()
        val n = s.size
        if (n == 0) return 0.0
        return if (n % 2 == 1) s[n / 2] else (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /** Direction changes of a sequence, ignoring wiggles smaller than [threshold] (zig-zag filter). */
    fun reversals(values: List<Double>, threshold: Double): Int {
        if (values.isEmpty()) return 0
        var ref = values[0]
        var direction = 0
        var count = 0
        for (v in values.drop(1)) {
            when (direction) {
                0 -> if (v - ref >= threshold) {
                    direction = 1
                    ref = v
                } else if (ref - v >= threshold) {
                    direction = -1
                    ref = v
                }
                1 -> if (v > ref) {
                    ref = v
                } else if (ref - v >= threshold) {
                    count += 1
                    direction = -1
                    ref = v
                }
                else -> if (v < ref) {
                    ref = v
                } else if (v - ref >= threshold) {
                    count += 1
                    direction = 1
                    ref = v
                }
            }
        }
        return count
    }
}

/** One-Euro filter for one scalar (Casiez et al.); dt in seconds. */
internal class OneEuroFilter(private val minCutoff: Double, private val beta: Double, private val dCutoff: Double) {
    private var x: Double? = null
    private var dx = 0.0

    fun filter(value: Double, dt: Double): Double {
        val prev = x ?: run {
            x = value
            return value
        }
        val d = (value - prev) / dt
        dx += alpha(dCutoff, dt) * (d - dx)
        val cutoff = minCutoff + beta * abs(dx)
        val next = prev + alpha(cutoff, dt) * (value - prev)
        x = next
        return next
    }

    companion object {
        fun alpha(cutoff: Double, dt: Double): Double {
            val tau = 1.0 / (2.0 * Math.PI * cutoff)
            return 1.0 / (1.0 + tau / dt)
        }
    }
}

/**
 * Push-up counter (doc 05 §4–5). Pure and deterministic: same input → same events as iOS and
 * tools/reference/pushly_ref/rep_engine.py (verified by shared/test-vectors/pushup).
 */
class RepEngine(val imageWidth: Double, val imageHeight: Double) {
    private object S {
        val oneEuro = PushupSpecV2.Smoothing.OneEuro
    }

    var state: RepState = RepState.NotReady
        private set
    var counted = 0
        private set
    var lastFeatures: RepFeatures? = null
        private set

    private val filters = HashMap<Int, OneEuroFilter>()
    private var leftSide: Boolean? = null
    private var switchFrames = 0
    private var lastT: Long? = null
    private val counts = HashMap<String, Int>()
    private var lowVisSince: Long? = null
    private var offPlankSince: Long? = null
    private var topShoulderY = 0.0
    private var fullTopY = 0.0
    private var topPeak = 0.0
    private var descMin = 180.0
    private var mode: Placement? = null
    private val armSamples = ArrayList<Double>()
    private var armRef = 0.0
    private var rep = ArrayList<RepFeatures>()
    private var repStart = 0L
    private var tBottom = 0L
    private var ascStart = 0L
    private var pendingFirst: RepFeatures? = null

    private fun smooth(key: Int, value: Double, dt: Double): Double =
        filters.getOrPut(key) { OneEuroFilter(S.oneEuro.MIN_CUTOFF, S.oneEuro.BETA, S.oneEuro.D_CUTOFF) }.filter(value, dt)

    internal fun features(frame: PoseFrame): RepFeatures {
        val t = frame.tMs
        val last = lastT
        val dt = if (last != null && t > last) (t - last) / 1000.0 else 1.0 / 30.0
        lastT = t
        val lm = frame.landmarks
        val w = frame.world
        val img = Array(33) { i -> doubleArrayOf(smooth(i * 5, lm[i].x, dt) * imageWidth, smooth(i * 5 + 1, lm[i].y, dt) * imageHeight) }
        val world = Array(33) { i ->
            doubleArrayOf(smooth(i * 5 + 2, w[i].x, dt), smooth(i * 5 + 3, w[i].y, dt), smooth(i * 5 + 4, w[i].z, dt))
        }
        val vis = DoubleArray(33) { lm[it].visibility }
        val req = PushupSpecV2.Visibility.REQUIRED_LANDMARK_MIN

        fun sideVis(left: Boolean): Double {
            val s = sides(left)
            return minOf(vis[s[0]], vis[s[1]], vis[s[2]], vis[s[3]], max(vis[s[4]], vis[s[5]]))
        }
        val vl = sideVis(true)
        val vr = sideVis(false)
        val current = leftSide
        if (current == null) {
            leftSide = vl >= vr
        } else {
            val cur = if (current) vl else vr
            val other = if (current) vr else vl
            if (other - cur > PushupSpecV2.Stability.SIDE_SWITCH_VISIBILITY_DELTA) {
                switchFrames += 1
                if (switchFrames >= PushupSpecV2.Stability.SIDE_SWITCH_FRAMES) {
                    leftSide = !current
                    switchFrames = 0
                }
            } else {
                switchFrames = 0
            }
        }
        val left = leftSide ?: true

        val shMid = doubleArrayOf((img[11][0] + img[12][0]) / 2, (img[11][1] + img[12][1]) / 2)
        val hipMid = doubleArrayOf((img[23][0] + img[24][0]) / 2, (img[23][1] + img[24][1]) / 2)
        val torsoLen = RepMath.dist(shMid, hipMid)
        val ratio = if (torsoLen > 1e-6) RepMath.dist(img[11], img[12]) / torsoLen else 99.0
        val placement = when {
            ratio < PushupSpecV2.Framing.PLACEMENT_SIDE_MAX_RATIO -> Placement.Side
            ratio > PushupSpecV2.Framing.PLACEMENT_FRONT_MIN_RATIO -> Placement.Front
            else -> Placement.Unknown
        }
        // v2: the measuring mode is locked while a set runs (Top…Recover); in NotReady it follows this frame.
        val frameMode = mode ?: if (placement == Placement.Front) Placement.Front else Placement.Side

        val (sh, el, wr) = sides(left).let { Triple(it[0], it[1], it[2]) }
        val (hip, kn, an) = sides(left).let { Triple(it[3], it[4], it[5]) }
        val ankleOk = vis[an] >= req
        val end = if (ankleOk) an else kn

        // v2: elbow angle from image pixels (world depth is unreliable side-on). Front: mean of both arms,
        // visibility = min over both arms (legs are hidden), no body line / tilt.
        val elbow: Double
        val sv: Double
        val bodyLine: Double
        val knee: Double
        val hipDev: Double
        val torsoTilt: Double
        if (frameMode == Placement.Front) {
            elbow = (RepMath.angle(img[11], img[13], img[15]) + RepMath.angle(img[12], img[14], img[16])) / 2
            sv = minOf(minOf(vis[11], vis[12], vis[13]), minOf(vis[14], vis[15], vis[16]))
            bodyLine = 180.0
            knee = 180.0
            hipDev = 0.0
            torsoTilt = 0.0
        } else {
            elbow = RepMath.angle(img[sh], img[el], img[wr])
            sv = if (left) vl else vr
            bodyLine = RepMath.angle(world[sh], world[hip], world[end])
            knee = if (ankleOk) RepMath.angle(world[hip], world[kn], world[an]) else 180.0
            val a = img[sh]
            val b = img[end]
            val h = img[hip]
            val yLine = if (abs(b[0] - a[0]) > 1e-6) a[1] + (b[1] - a[1]) * (h[0] - a[0]) / (b[0] - a[0]) else h[1]
            hipDev = h[1] - yLine
            torsoTilt = Math.toDegrees(atan2(abs(b[1] - a[1]), abs(b[0] - a[0])))
        }

        var minX = Double.POSITIVE_INFINITY
        var maxX = Double.NEGATIVE_INFINITY
        var minY = Double.POSITIVE_INFINITY
        var maxY = Double.NEGATIVE_INFINITY
        var any = false
        for (i in 0 until 33) {
            if (vis[i] < PushupSpecV2.Framing.BBOX_VISIBILITY_MIN) continue
            any = true
            minX = min(minX, lm[i].x)
            maxX = max(maxX, lm[i].x)
            minY = min(minY, lm[i].y)
            maxY = max(maxY, lm[i].y)
        }
        val bbox = if (any) max(maxX - minX, maxY - minY) else 0.0

        val shoulderY: Double
        val upperArm: Double
        if (frameMode == Placement.Front) {
            shoulderY = shMid[1]
            upperArm = (RepMath.dist(img[11], img[13]) + RepMath.dist(img[12], img[14])) / 2
        } else {
            shoulderY = img[sh][1]
            upperArm = RepMath.dist(img[sh], img[el])
        }
        val wristDrop = (img[15][1] + img[16][1]) / 2 - shMid[1]
        return RepFeatures(
            t = t, leftSide = left, visibility = sv, elbow = elbow, bodyLine = bodyLine, knee = knee, hipDeviation = hipDev,
            torsoTilt = torsoTilt, bbox = bbox, shoulderY = shoulderY, upperArm = upperArm,
            placement = placement, motion = frame.motion, mode = frameMode, wristDrop = wristDrop,
        )
    }

    private fun stable(name: String, cond: Boolean): Boolean {
        if (!cond) {
            counts[name] = 0
            return false
        }
        val n = (counts[name] ?: 0) + 1
        if (n >= PushupSpecV2.Stability.STABLE_FRAMES) {
            counts[name] = 0
            return true
        }
        counts[name] = n
        return false
    }

    private fun enter(s: RepState) {
        state = s
        counts.clear()
        if (s == RepState.NotReady) mode = null
        if (s == RepState.Top) topPeak = 0.0
    }

    private fun bottomMax(f: RepFeatures): Double =
        if (f.mode == Placement.Front) PushupSpecV2.Elbow.FRONT_BOTTOM_MAX_DEG else PushupSpecV2.Elbow.BOTTOM_MAX_DEG

    private fun depth(f: RepFeatures): Double = if (armRef > 1e-6) (f.shoulderY - topShoulderY) / armRef else 0.0

    private fun updateTop(f: RepFeatures) {
        topShoulderY = f.shoulderY
        if (f.elbow >= PushupSpecV2.Elbow.TOP_MIN_DEG) fullTopY = f.shoulderY
        armSamples += f.upperArm
        if (armSamples.size > 30) armSamples.removeAt(0)
        armRef = RepMath.median(armSamples)
    }

    /**
     * Top of a rep (v2): arms straight (≥ topMinDeg), or nearly straight (≥ lockoutMinDeg) with the shoulder back within
     * depth.lockoutMaxRatio upper arms of the set's last full-lockout height.
     */
    private fun lockedOut(f: RepFeatures): Boolean {
        if (f.elbow >= PushupSpecV2.Elbow.TOP_MIN_DEG) return true
        if (armRef <= 1e-6) return false
        val rise = (f.shoulderY - fullTopY) / armRef
        return f.elbow >= PushupSpecV2.Elbow.LOCKOUT_MIN_DEG && rise <= PushupSpecV2.Depth.LOCKOUT_MAX_RATIO
    }

    /** Feeds one frame; returns the events it produced (usually none). */
    fun process(frame: PoseFrame): List<RepEvent> {
        val events = ArrayList<RepEvent>()
        val f = features(frame)
        lastFeatures = f
        val topMin = PushupSpecV2.Elbow.TOP_MIN_DEG

        val lostMs = PushupSpecV2.Stability.TRACKING_LOST_MS.toLong()
        if (f.visibility < PushupSpecV2.Visibility.LOST_BELOW) {
            if (lowVisSince == null) lowVisSince = f.t
        } else {
            lowVisSince = null
        }
        val offPlank = if (f.mode == Placement.Front) {
            f.wristDrop < PushupSpecV2.Front.LOST_WRIST_DROP_MAX * f.upperArm
        } else {
            f.torsoTilt > PushupSpecV2.Plank.TORSO_TILT_MAX_DEG
        }
        if (offPlank) {
            if (offPlankSince == null) offPlankSince = f.t
        } else {
            offPlankSince = null
        }
        val visLost = lowVisSince?.let { f.t - it >= lostMs } ?: false
        val plankLost = offPlankSince?.let { f.t - it >= lostMs } ?: false
        if (state != RepState.NotReady && (visLost || plankLost)) {
            if (state in setOf(RepState.Descending, RepState.Bottom, RepState.Ascending) && visLost) {
                events += RepEvent.Rejected(RejectReason.BodyNotVisible, f.t)
            }
            rep = ArrayList()
            enter(RepState.NotReady)
            return events
        }

        when (state) {
            RepState.NotReady -> {
                val plank = if (f.mode == Placement.Front) {
                    // Front (v2): legs are out of view — hands on the floor well below the shoulders, arms straight.
                    f.placement == Placement.Front && f.elbow >= topMin &&
                        f.visibility >= PushupSpecV2.Visibility.REQUIRED_LANDMARK_MIN &&
                        f.wristDrop >= PushupSpecV2.Front.PLANK_WRIST_DROP_MIN * f.upperArm
                } else {
                    f.torsoTilt <= PushupSpecV2.Plank.TORSO_TILT_MAX_DEG && f.bodyLine >= PushupSpecV2.Plank.BODY_LINE_MIN_DEG &&
                        f.elbow >= topMin && f.visibility >= PushupSpecV2.Visibility.REQUIRED_LANDMARK_MIN &&
                        PushupSpecV2.Plank.BBOX_HEIGHT_MIN <= f.bbox && f.bbox <= PushupSpecV2.Plank.BBOX_HEIGHT_MAX &&
                        f.placement != Placement.Unknown
                }
                if (stable("plank", plank)) {
                    armSamples.clear()
                    updateTop(f)
                    enter(RepState.Top)
                    mode = f.mode
                }
            }
            RepState.Top -> {
                // v2: the descent starts below the arm angle actually reached at this top (relaxed lockout).
                topPeak = max(topPeak, f.elbow)
                val cond = f.elbow < min(topMin - PushupSpecV2.Elbow.HYSTERESIS_DEG, topPeak - PushupSpecV2.Elbow.DESCENT_DROP_DEG)
                if (cond && (counts["down"] ?: 0) == 0) pendingFirst = f
                if (stable("down", cond)) {
                    val first = pendingFirst ?: f
                    rep = if (first == f) ArrayList() else arrayListOf(first)
                    rep += f
                    repStart = first.t
                    descMin = f.elbow
                    enter(RepState.Descending)
                } else if (!cond) {
                    updateTop(f)
                }
            }
            RepState.Descending -> {
                rep += f
                descMin = min(descMin, f.elbow)
                if (stable("bottom", f.elbow <= bottomMax(f) && depth(f) >= PushupSpecV2.Depth.MIN_DEPTH_RATIO)) {
                    tBottom = f.t
                    enter(RepState.Bottom)
                } else if (stable("upNoBottom", lockedOut(f) && f.elbow - descMin >= PushupSpecV2.Elbow.DESCENT_DROP_DEG)) {
                    events += RepEvent.Rejected(RejectReason.NotDeepEnough, f.t)
                    rep = ArrayList()
                    updateTop(f)
                    enter(RepState.Top)
                }
            }
            RepState.Bottom -> {
                rep += f
                if (stable("up", f.elbow > bottomMax(f) + PushupSpecV2.Elbow.HYSTERESIS_DEG)) {
                    ascStart = f.t
                    enter(RepState.Ascending)
                }
            }
            RepState.Ascending -> {
                rep += f
                if (stable("lockout", lockedOut(f))) {
                    evaluate(f.t)?.let { events += it }
                    rep = ArrayList()
                    updateTop(f)
                    enter(RepState.Top)
                } else if (f.t - ascStart > PushupSpecV2.Elbow.LOCKOUT_WAIT_MS || stable("downAgain", f.elbow <= bottomMax(f))) {
                    events += RepEvent.Rejected(RejectReason.NoLockout, f.t)
                    rep = ArrayList()
                    enter(RepState.Recover)
                }
            }
            RepState.Recover -> {
                if (stable("recovered", lockedOut(f))) {
                    updateTop(f)
                    enter(RepState.Top)
                }
            }
        }
        return events
    }

    private fun evaluate(tEnd: Long): RepEvent? {
        val frames = rep
        if (frames.isEmpty()) return null
        val n = frames.size.toDouble()
        if (frames.count { it.visibility >= PushupSpecV2.Visibility.REQUIRED_LANDMARK_MIN } / n <
            PushupSpecV2.Visibility.REQUIRED_FRAME_SHARE
        ) {
            return RepEvent.Rejected(RejectReason.BodyNotVisible, tEnd)
        }
        if (frames.count { it.knee >= PushupSpecV2.Form.KNEE_MIN_DEG } / n < PushupSpecV2.Form.KNEE_FRAME_SHARE) {
            return RepEvent.Rejected(RejectReason.KneesDown, tEnd)
        }
        val bad = frames.filter { it.bodyLine < PushupSpecV2.Form.BODY_LINE_MIN_DEG }
        if ((n - bad.size) / n < PushupSpecV2.Form.BODY_LINE_FRAME_SHARE) {
            val meanDev = bad.sumOf { it.hipDeviation } / bad.size
            return RepEvent.Rejected(if (meanDev > 0) RejectReason.HipsSagging else RejectReason.HipsPiked, tEnd)
        }
        val duration = tEnd - repStart
        if (duration < PushupSpecV2.Tempo.MIN_REP_MS) return RepEvent.Rejected(RejectReason.TooFast, tEnd)
        if (duration > PushupSpecV2.Tempo.MAX_REP_MS) return RepEvent.Rejected(RejectReason.TooSlow, tEnd)
        if (RepMath.reversals(frames.map { it.elbow }, PushupSpecV2.Form.MAX_DIRECTION_REVERSALS_DEG) > 1) {
            return RepEvent.Rejected(RejectReason.IrregularMotion, tEnd)
        }
        val motions = frames.mapNotNull { it.motion }
        if (motions.isNotEmpty()) {
            val shaky = motions.count { it > PushupSpecV2.Integrity.DEVICE_MOTION_MAX_RMS }.toDouble() / motions.size
            if (shaky > PushupSpecV2.Integrity.DEVICE_MOTION_FRAME_SHARE) return RepEvent.Rejected(RejectReason.Integrity, tEnd)
        }

        val maxDepth = frames.maxOf { depth(it) }
        val maxElbow = frames.maxOf { it.elbow }
        val minElbow = frames.minOf { it.elbow }
        val minLine = frames.minOf { it.bodyLine }
        val meanLine = frames.sumOf { it.bodyLine } / n
        val depthS = RepMath.clamp01((maxDepth - PushupSpecV2.Depth.MIN_DEPTH_RATIO) / 0.40)
        val lockS = RepMath.clamp01((maxElbow - PushupSpecV2.Elbow.TOP_MIN_DEG) / 20.0)
        // Front cannot see the body line: neutral half score.
        val lineS = if (frames.last().mode == Placement.Front) 0.5 else RepMath.clamp01((meanLine - PushupSpecV2.Form.BODY_LINE_MIN_DEG) / 25.0)
        val d = duration.toDouble()
        val tempoS = when {
            duration < 1000 -> RepMath.clamp01((d - PushupSpecV2.Tempo.MIN_REP_MS) / 550.0)
            duration <= 3000 -> 1.0
            else -> RepMath.clamp01(1.0 - (d - 3000) / 5000.0)
        }
        val w = PushupSpecV2.Quality.Weights
        val q = w.DEPTH * depthS + w.LOCKOUT * lockS + w.BODY_LINE * lineS + w.TEMPO * tempoS
        counted += 1
        return RepEvent.Counted(
            CountedRep(counted, floor(100 * q + 0.5).toInt(), repStart, tBottom, tEnd, minElbow, maxElbow, minLine, maxDepth),
        )
    }

    private companion object {
        val LEFT = intArrayOf(11, 13, 15, 23, 25, 27)
        val RIGHT = intArrayOf(12, 14, 16, 24, 26, 28)
        fun sides(left: Boolean) = if (left) LEFT else RIGHT
    }
}

object RepEngineInfo {
    const val SPEC_VERSION: Int = PushupSpecV2.SPEC_VERSION
}
