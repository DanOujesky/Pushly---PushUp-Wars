package app.pushly.feature.wakeflow

import app.pushly.engine.rep.CountedRep
import app.pushly.engine.rep.RejectReason
import app.pushly.engine.rep.RepEngineInfo
import app.pushly.engine.rep.SessionMonitor
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import kotlin.math.roundToLong

/**
 * The rep log uploaded to submit-rep-session (shared/contracts/rep-log.schema.json, doc 06 §3). Same JSON as iOS.
 * Rep / set times are milliseconds since the session start on the monotonic clock.
 */
@Serializable
data class RepLog(
    val sessionId: String,
    val deviceId: String? = null,
    val context: Context,
    val specVersion: Int,
    val appVersion: String,
    val platform: String = "android",
    val deviceModel: String,
    val timing: Timing,
    /** completed | gaveUp | expired */
    val outcome: String,
    val snoozes: Int = 0,
    val sprintStartMs: Long? = null,
    val sets: List<SetSpan> = emptyList(),
    val reps: List<Rep>,
    val rejected: Map<String, Int>,
    /** 10 Hz feature trace (SessionMonitor): JSON, raw deflate, base64 — never video. */
    val featureTrace: String? = null,
    val suspicion: Suspicion,
    val signature: String? = null,
) {
    @Serializable data class Context(val type: String, val occurrenceId: String? = null)

    @Serializable data class Anchor(val serverTime: String, val monotonicAtAnchorMs: Long)

    @Serializable data class Timing(
        val monotonicStartMs: Long,
        val monotonicEndMs: Long,
        val wallStart: String,
        val serverAnchor: Anchor? = null,
        val ringStartedAtMonotonicMs: Long? = null,
    )

    @Serializable data class Rep(
        val i: Int,
        val tStartMs: Long,
        val tBottomMs: Long,
        val tEndMs: Long,
        val quality: Int,
        val minElbow: Double? = null,
        val maxElbow: Double? = null,
        val minBodyLine: Double? = null,
        val depth: Double? = null,
    )

    @Serializable data class SetSpan(val startMs: Long, val endMs: Long)

    @Serializable data class Suspicion(val replay: Double, val motion: Double, val continuity: Double, val liveness: String)

    fun encode(): String = JSON.encodeToString(serializer(), this)

    companion object {
        /** Nulls are left out (the schema treats missing and null alike). */
        val JSON = Json {
            explicitNulls = false
            encodeDefaults = true
            ignoreUnknownKeys = true
        }
    }
}

/** Server anchor for rep timestamps: server epoch ms at a monotonic instant (doc 06 §3, T5 clock tampering). */
data class ServerAnchor(val serverMs: Long, val monotonicMs: Long) {
    companion object {
        /** Measures one round trip and assumes the server read its clock half way. */
        suspend fun measure(monotonic: () -> Long, fetch: suspend () -> Long): ServerAnchor {
            val before = monotonic()
            val server = fetch()
            val after = monotonic()
            return ServerAnchor(server, before + (after - before) / 2)
        }
    }
}

/**
 * Collects the timeline of one camera session on the monotonic clock: reps (converted from camera frame time), set
 * and sprint markers. Same rules as iOS `RepTimeline`.
 */
class RepTimeline(val monotonicStartMs: Long, val wallStartMs: Long) {
    var monotonicEndMs: Long? = null
        private set
    /** monotonic − camera frame time, measured at the first frame (camera clocks differ per device). */
    var frameOffsetMs: Long? = null
        private set
    val reps = ArrayList<RepLog.Rep>()
    val sets = ArrayList<RepLog.SetSpan>()
    var sprintStartMs: Long? = null
        private set

    fun frame(tMs: Long, monotonicNow: Long) {
        if (frameOffsetMs == null) frameOffsetMs = monotonicNow - tMs
    }

    /** Session-relative ms of a camera frame time (the same clock as reps, sets and the feature trace). */
    fun relative(frameMs: Long): Long = maxOf(0, frameMs + (frameOffsetMs ?: 0) - monotonicStartMs)

    private fun rel(frameMs: Long): Long = relative(frameMs)

    fun counted(rep: CountedRep, index: Int) {
        reps += RepLog.Rep(
            i = index, tStartMs = rel(rep.tStart), tBottomMs = rel(rep.tBottom), tEndMs = rel(rep.tEnd),
            quality = rep.quality, minElbow = round1(rep.minElbow), maxElbow = round1(rep.maxElbow),
            minBodyLine = round1(rep.minBodyLine), depth = (rep.depth * 1000).roundToLong() / 1000.0,
        )
    }

    /** A finished set, in session-relative ms (sets mode: first rep start → last rep end). */
    fun appendSet(startMs: Long, endMs: Long) {
        sets += RepLog.SetSpan(startMs, maxOf(startMs, endMs))
    }

    fun startSprint(monotonicNow: Long) {
        if (sprintStartMs == null) sprintStartMs = monotonicNow - monotonicStartMs
    }

    fun end(monotonicNow: Long) {
        if (monotonicEndMs == null) monotonicEndMs = maxOf(monotonicNow, monotonicStartMs + (reps.lastOrNull()?.tEndMs ?: 0))
    }

    private fun round1(v: Double): Double = (v * 10).roundToLong() / 10.0

    fun log(
        sessionId: String,
        context: String,
        occurrenceId: String?,
        outcome: String,
        snoozes: Int,
        rejected: Map<RejectReason, Int>,
        anchor: ServerAnchor?,
        ringAtMonotonicMs: Long?,
        appVersion: String,
        deviceModel: String,
        monitor: SessionMonitor? = null,
    ): RepLog = RepLog(
        sessionId = sessionId,
        context = RepLog.Context(context, occurrenceId),
        specVersion = RepEngineInfo.SPEC_VERSION,
        appVersion = appVersion,
        deviceModel = deviceModel,
        timing = RepLog.Timing(
            monotonicStartMs = monotonicStartMs,
            monotonicEndMs = monotonicEndMs ?: monotonicStartMs,
            wallStart = Instant.ofEpochMilli(wallStartMs).toString(),
            serverAnchor = anchor?.let { RepLog.Anchor(Instant.ofEpochMilli(it.serverMs).toString(), it.monotonicMs) },
            ringStartedAtMonotonicMs = ringAtMonotonicMs?.let { maxOf(0, it) },
        ),
        outcome = outcome,
        snoozes = snoozes,
        sprintStartMs = sprintStartMs,
        sets = sets.toList(),
        reps = reps.toList(),
        rejected = rejected.mapKeys { it.key.code },
        featureTrace = monitor?.encodedTrace(),
        suspicion = RepLog.Suspicion(monitor?.replay ?: 0.0, 0.0, monitor?.continuity ?: 0.0, "n/a"),
    )
}
