package app.pushly.feature.wakeflow

import app.pushly.engine.pose.PoseSessionStatus
import app.pushly.engine.rep.Guidance
import app.pushly.engine.rep.HintGate
import app.pushly.engine.rep.PoseFrame
import app.pushly.engine.rep.PoseLandmark
import app.pushly.engine.rep.RejectReason
import app.pushly.engine.rep.RepEngine
import app.pushly.engine.rep.RepEvent
import app.pushly.engine.rep.RepState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.math.roundToInt

/**
 * One camera push-up session (doc 05): feeds pose frames into [RepEngine], keeps count, hints and guidance.
 * Pure state (no Android APIs) so it is unit-tested with the shared vectors; same behaviour as iOS RepSessionModel.
 */
class RepSessionModel(
    val mode: Mode,
    private val now: () -> Long = System::currentTimeMillis,
    private val onCounted: (Int) -> Unit = {},
    private val onFinished: (Summary) -> Unit = {},
    /** Debug builds only: raw frames for the pose recorder (P3-04). */
    val recorder: PoseRecorder? = null,
) {
    sealed interface Mode {
        /** Wake challenge: count up to [target], then finish. */
        data class Wake(val target: Int) : Mode

        /** Free training (PS-80): count until the user ends the session. */
        data object Training : Mode
    }

    data class Summary(val reps: Int, val averageQuality: Int, val rejected: Map<RejectReason, Int>, val durationSeconds: Int)

    data class State(
        val counted: Int = 0,
        val lastQuality: Int? = null,
        val hint: HintGate.Hint? = null,
        val guidance: Guidance = Guidance.StepIntoFrame,
        val repState: RepState = RepState.NotReady,
        val landmarks: List<PoseLandmark> = emptyList(),
        val status: PoseSessionStatus = PoseSessionStatus(),
        val finished: Boolean = false,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var engine: RepEngine? = null
    private var countedBefore = 0
    private val gate = HintGate()
    private val qualities = ArrayList<Int>()
    private val rejected = HashMap<RejectReason, Int>()
    private var startedAt = now()

    val target: Int? get() = (mode as? Mode.Wake)?.target

    fun remaining(): Int? = target?.let { maxOf(it - _state.value.counted, 0) }

    fun summary(): Summary = Summary(
        reps = _state.value.counted,
        averageQuality = if (qualities.isEmpty()) 0 else (qualities.sum().toDouble() / qualities.size).roundToInt(),
        rejected = rejected.toMap(),
        durationSeconds = ((now() - startedAt) / 1000).toInt(),
    )

    fun restartClock() {
        startedAt = now()
    }

    fun updateStatus(s: PoseSessionStatus) {
        _state.update { it.copy(status = s) }
        refreshGuidance()
    }

    /** Feeds one pose frame. [width]/[height] = upright frame size in pixels. */
    fun ingest(frame: PoseFrame, width: Int, height: Int) {
        if (_state.value.finished) return
        val current = engine
        val e = if (current != null && current.imageWidth == width.toDouble() && current.imageHeight == height.toDouble()) {
            current
        } else {
            countedBefore = _state.value.counted
            RepEngine(width.toDouble(), height.toDouble()).also { engine = it }
        }
        recorder?.append(frame, width, height)
        var s = _state.value.copy(landmarks = frame.landmarks)
        for (event in e.process(frame)) {
            when (event) {
                is RepEvent.Counted -> {
                    s = s.copy(counted = countedBefore + event.rep.index, lastQuality = event.rep.quality, hint = null)
                    qualities += event.rep.quality
                    onCounted(s.counted)
                }
                is RepEvent.Rejected -> {
                    rejected[event.reason] = (rejected[event.reason] ?: 0) + 1
                    gate.offer(event.reason, event.t)?.let { s = s.copy(hint = it) }
                }
            }
        }
        _state.value = s.copy(repState = e.state)
        refreshGuidance()
        val t = target
        if (t != null && _state.value.counted >= t) finish()
    }

    private fun refreshGuidance() {
        val s = _state.value
        _state.value = s.copy(guidance = Guidance.current(s.repState, engine?.lastFeatures, s.status.personVisible, s.status.tooDark))
    }

    /** Ends the session (target reached, or the user ends free training). */
    fun finish() {
        if (_state.value.finished) return
        _state.update { it.copy(finished = true) }
        onFinished(summary())
    }
}
