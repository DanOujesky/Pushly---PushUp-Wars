package app.pushly.feature.wakeflow

import android.os.Build
import app.pushly.core.common.AppClock
import app.pushly.core.common.JvmClock
import app.pushly.engine.pose.PoseSessionStatus
import app.pushly.engine.rep.Guidance
import app.pushly.engine.rep.HintGate
import app.pushly.engine.rep.PoseFrame
import app.pushly.engine.rep.Placement
import app.pushly.engine.rep.PoseLandmark
import app.pushly.engine.rep.RejectReason
import app.pushly.engine.rep.RepEngine
import app.pushly.engine.rep.RepEvent
import app.pushly.engine.rep.RepState
import app.pushly.engine.rep.SessionMonitor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.math.roundToInt

/**
 * One camera push-up session (doc 05): feeds pose frames into [RepEngine], keeps count, hints and guidance, and the
 * timeline that becomes the uploaded rep log (doc 06 §3). Pure state (no Android APIs except the device model), so it
 * is unit-tested with the shared vectors; same behaviour as iOS RepSessionModel.
 */
class RepSessionModel(
    val mode: Mode,
    private val clock: AppClock = JvmClock,
    private val onFinished: (Summary) -> Unit = {},
    /** Debug builds only: raw frames for the pose recorder (P3-04). */
    val recorder: PoseRecorder? = null,
    /** false in battles: FRONT can't see the knees, so only the side view counts (D-064). */
    val allowFront: Boolean = true,
) {
    sealed interface Mode {
        /** Wake challenge: count up to [target], then finish. */
        data class Wake(val target: Int) : Mode

        /** Free training (PS-80): count until the user ends the session. */
        data object Training : Mode

        /** Counting only; the owner decides when it is over (wake modes sprint / sets drive it themselves). */
        data object Open : Mode
    }

    data class Summary(val reps: Int, val averageQuality: Int, val rejected: Map<RejectReason, Int>, val durationSeconds: Int)

    /** Replaces the big counter (e.g. "7 / 10" of the current set, sprint seconds left). */
    data class CounterDisplay(val value: String, val caption: String, val progress: Float? = null)

    data class State(
        val counted: Int = 0,
        val lastQuality: Int? = null,
        val hint: HintGate.Hint? = null,
        val guidance: Guidance = Guidance.StepIntoFrame,
        val repState: RepState = RepState.NotReady,
        val landmarks: List<PoseLandmark> = emptyList(),
        val status: PoseSessionStatus = PoseSessionStatus(),
        val finished: Boolean = false,
        val display: CounterDisplay? = null,
        /** Counting from the front (legs not visible): reps count for the alarm and stats, not leaderboards (D-064). */
        val frontMode: Boolean = false,
        /** Increments on every rejected rep (the screen plays the "miss" sound). */
        val rejectedCount: Int = 0,
        /** Push-ups counted from the FRONT this session — any makes the session personal only (D-064, D-070). */
        val frontReps: Int = 0,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Battle video (doc 07 §5): the same upright camera frames also go to LiveKit. Called on the camera thread. */
    @Volatile var videoTap: ((android.graphics.Bitmap) -> Unit)? = null

    /** Called on every counted rep with the session total (wake modes react to it). */
    @Volatile var onCounted: ((Int) -> Unit)? = null

    var outcome: String = "completed"
        private set
    var timeline: RepTimeline? = null
        private set

    /** Feed continuity, limb-length wobble and the 10 Hz feature trace (doc 06 §2). */
    val monitor = SessionMonitor()

    private var engine: RepEngine? = null
    private var countedBefore = 0
    private val gate = HintGate()
    private val qualities = ArrayList<Int>()
    private val rejected = HashMap<RejectReason, Int>()
    private var startedAt = clock.nowMs()

    val target: Int? get() = (mode as? Mode.Wake)?.target
    val monotonicNowMs: Long get() = clock.monotonicMs()
    val nowMs: Long get() = clock.nowMs()

    fun remaining(): Int? = target?.let { maxOf(it - _state.value.counted, 0) }

    fun summary(): Summary = Summary(
        reps = _state.value.counted,
        averageQuality = if (qualities.isEmpty()) 0 else (qualities.sum().toDouble() / qualities.size).roundToInt(),
        rejected = rejected.toMap(),
        durationSeconds = ((clock.nowMs() - startedAt) / 1000).toInt(),
    )

    fun restartClock() {
        startedAt = clock.nowMs()
        if (timeline == null) timeline = RepTimeline(clock.monotonicMs(), startedAt)
    }

    fun updateStatus(s: PoseSessionStatus) {
        _state.update { it.copy(status = s) }
        refreshGuidance()
    }

    fun setDisplay(display: CounterDisplay?) {
        _state.update { it.copy(display = display) }
    }

    /** Feeds one pose frame. [width]/[height] = upright frame size in pixels. */
    fun ingest(frame: PoseFrame, width: Int, height: Int) {
        if (_state.value.finished) return
        // Someone else in the frame: pause counting until they leave (doc 06 §2.2).
        if (_state.value.status.multiplePeople) {
            _state.update { it.copy(landmarks = frame.landmarks) }
            return
        }
        val current = engine
        val e = if (current != null && current.imageWidth == width.toDouble() && current.imageHeight == height.toDouble()) {
            current
        } else {
            countedBefore = _state.value.counted
            RepEngine(width.toDouble(), height.toDouble(), allowFront).also { engine = it }
        }
        recorder?.append(frame, width, height)
        val tl = timeline ?: RepTimeline(clock.monotonicMs(), clock.nowMs()).also { timeline = it }
        tl.frame(frame.tMs, clock.monotonicMs())
        var s = _state.value.copy(landmarks = frame.landmarks)
        val events = e.process(frame)
        monitor.frame(frame, e.lastFeatures, tl.relative(frame.tMs))
        for (event in events) {
            when (event) {
                is RepEvent.Counted -> {
                    s = s.copy(counted = countedBefore + event.rep.index, lastQuality = event.rep.quality, hint = null)
                    qualities += event.rep.quality
                    tl.counted(event.rep, s.counted)
                    s = s.copy(frontReps = tl.frontReps)
                }
                is RepEvent.Rejected -> {
                    rejected[event.reason] = (rejected[event.reason] ?: 0) + 1
                    s = s.copy(rejectedCount = s.rejectedCount + 1)
                    gate.offer(event.reason, event.t)?.let { s = s.copy(hint = it) }
                }
            }
        }
        val before = _state.value.counted
        _state.value = s.copy(repState = e.state,
            frontMode = e.state != RepState.NotReady && e.lastFeatures?.mode == Placement.Front)
        refreshGuidance()
        if (_state.value.counted != before) onCounted?.invoke(_state.value.counted)
        val t = target
        if (t != null && _state.value.counted >= t) finish()
    }

    private fun refreshGuidance() {
        val s = _state.value
        _state.value = s.copy(guidance = Guidance.current(s.repState, engine?.lastFeatures, s.status.personVisible, s.status.tooDark, allowFront))
    }

    // Markers (wake modes)

    fun appendSet(startMs: Long, endMs: Long) {
        timeline?.appendSet(startMs, endMs)
    }

    private var openSetStart: Long? = null

    /** Workouts (D-069): a set starts / ends now (same as iOS markSetStart / markSetEnd). */
    fun markSetStart() {
        openSetStart = clock.monotonicMs()
    }

    fun markSetEnd() {
        val start = openSetStart ?: return
        val tl = timeline ?: return
        tl.appendSet(maxOf(0, start - tl.monotonicStartMs), clock.monotonicMs() - tl.monotonicStartMs)
        openSetStart = null
    }

    fun markSprintStart() {
        timeline?.startSprint(clock.monotonicMs())
    }

    /** Ends the session (target reached, the user ends training, gives up — "gaveUp" — or time ran out). */
    fun finish(outcome: String = "completed") {
        if (_state.value.finished) return
        this.outcome = outcome
        val tl = timeline ?: RepTimeline(clock.monotonicMs(), clock.nowMs()).also { timeline = it }
        tl.end(clock.monotonicMs())
        _state.update { it.copy(finished = true) }
        onFinished(summary())
    }

    /** The upload for this session (after [finish]). [ringAtMs]: when the alarm rang, wall clock (wake only). */
    fun repLog(
        sessionId: String,
        context: String,
        appVersion: String,
        occurrenceId: String? = null,
        snoozes: Int = 0,
        anchor: ServerAnchor? = null,
        ringAtMs: Long? = null,
        battleId: String? = null,
    ): RepLog {
        val tl = timeline ?: RepTimeline(clock.monotonicMs(), clock.nowMs())
        val ringMono = ringAtMs?.let { clock.monotonicMs() - (clock.nowMs() - it) }
        return tl.log(sessionId, context, occurrenceId, outcome, snoozes, rejected.toMap(), anchor, ringMono, appVersion, deviceModel(), monitor, battleId)
    }

    private fun deviceModel(): String = (Build.MANUFACTURER ?: "") + " " + (Build.MODEL ?: "")
}
