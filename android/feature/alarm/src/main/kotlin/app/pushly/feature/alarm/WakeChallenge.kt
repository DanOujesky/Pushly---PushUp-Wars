package app.pushly.feature.alarm

import app.pushly.core.alarm.ModeType
import app.pushly.core.alarm.RingState
import app.pushly.core.alarm.WakeRules
import app.pushly.engine.rep.RepState
import app.pushly.feature.wakeflow.RepSessionModel
import app.pushly.feature.wakeflow.ServerAnchor
import app.pushly.feature.wakeflow.SessionServices
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/**
 * Runs one wake challenge in the camera (doc 04 §3, PS-30…PS-34): applies the mode rules live, finishes the camera
 * session, decides the provisional result with [WakeRules] (same rules as the server) and queues the rep log. The
 * server's answer replaces the provisional result when it arrives (PS-90). Same behaviour as iOS `WakeChallengeModel`.
 * [tick] must be called a few times per second while the screen is open.
 */
class WakeChallenge(
    val ring: RingState,
    private val services: SessionServices?,
    /** Called once when the challenge is over; `true` = provisional success. */
    private val onOver: (Boolean) -> Unit = {},
    /** Sets: the rest is over — ring loudly until the next set starts. */
    private val onRestOver: () -> Unit = {},
    /** Sets: the next set started — back to the quiet sound. */
    private val onSetStarted: () -> Unit = {},
    model: RepSessionModel? = null,
) {
    sealed interface Phase {
        data object Counting : Phase
        data object SprintReady : Phase
        data class SprintCountdown(val left: Int) : Phase
        data class Sprinting(val endsAtMs: Long) : Phase
        data class Rest(val endsAtMs: Long, val startByMs: Long) : Phase
        data object Done : Phase
    }

    private val type: ModeType = ring.mode.modeType ?: ModeType.RingUntilDone
    val sessionId: String = UUID.randomUUID().toString()
    val reps: RepSessionModel = model ?: when (type) {
        ModeType.Sprint, ModeType.Sets -> RepSessionModel(RepSessionModel.Mode.Open)
        else -> RepSessionModel(RepSessionModel.Mode.Wake(maxOf(ring.target, 1)))
    }

    private val _phase = MutableStateFlow<Phase>(if (type == ModeType.Sprint) Phase.SprintReady else Phase.Counting)
    val phase: StateFlow<Phase> = _phase.asStateFlow()
    private val _decision = MutableStateFlow<WakeRules.Decision?>(null)
    val decision: StateFlow<WakeRules.Decision?> = _decision.asStateFlow()

    var anchor: ServerAnchor? = null
    var setIndex = 0
        private set
    private var sprintStartCount = 0
    private var setStartCount = 0
    private var countdownStartedMs = 0L
    private var restOverSignalled = false

    init {
        reps.onCounted = { counted(it) }
        refreshDisplay()
    }

    fun giveUp() = finish("gaveUp")

    fun tick() {
        val p = _phase.value
        if (p == Phase.Done) return
        if (reps.nowMs >= ring.deadline.toEpochMilli()) {
            finish("expired")
            return
        }
        val mono = reps.monotonicNowMs
        when (p) {
            Phase.SprintReady -> if (reps.state.value.repState != RepState.NotReady) {
                countdownStartedMs = mono
                _phase.value = Phase.SprintCountdown(3)
            }
            is Phase.SprintCountdown -> {
                val left = 3 - ((mono - countdownStartedMs) / 1000).toInt()
                if (left <= 0) {
                    reps.markSprintStart()
                    sprintStartCount = reps.state.value.counted
                    _phase.value = Phase.Sprinting(mono + (ring.mode.windowSeconds ?: 60) * 1000L)
                } else if (left != p.left) {
                    _phase.value = Phase.SprintCountdown(left)
                }
            }
            is Phase.Sprinting -> if (mono >= p.endsAtMs) {
                finish("completed")
                return
            }
            is Phase.Rest -> {
                if (mono >= p.startByMs) {
                    finish("expired") // next set not started in time (rest + 30 s)
                    return
                }
                if (mono >= p.endsAtMs && !restOverSignalled) {
                    restOverSignalled = true
                    onRestOver()
                }
            }
            Phase.Counting, Phase.Done -> Unit
        }
        refreshDisplay()
    }

    private fun counted(total: Int) {
        when (type) {
            ModeType.RingUntilDone, ModeType.Escalation, ModeType.BeatTheClock -> if (total >= ring.target) {
                finish("completed")
                return
            }
            ModeType.Sets -> {
                if (_phase.value is Phase.Rest) {
                    // The first rep of the next set ends the rest.
                    setIndex++
                    setStartCount = total - 1
                    _phase.value = Phase.Counting
                    onSetStarted()
                }
                if (total - setStartCount >= (ring.mode.repsPerSet ?: 1)) closeSet(total)
            }
            ModeType.Sprint -> Unit
        }
        refreshDisplay()
    }

    /** The set's span runs from its first rep's start to its last rep's end (server rule, doc 04 §3 sets). */
    private fun closeSet(total: Int) {
        val timeline = reps.timeline ?: return
        val setReps = timeline.reps.takeLast(total - setStartCount)
        val first = setReps.firstOrNull()
        val last = setReps.lastOrNull()
        if (first != null && last != null) reps.appendSet(first.tStartMs, last.tEndMs)
        if (setIndex + 1 >= (ring.mode.sets ?: 1)) {
            finish("completed")
            return
        }
        val mono = reps.monotonicNowMs
        val rest = (ring.mode.restSeconds ?: 0) * 1000L
        restOverSignalled = false
        _phase.value = Phase.Rest(mono + rest, mono + rest + WakeRules.SET_START_GRACE_S * 1000L)
    }

    /** Counter content for sprint / sets; the screen turns it into text (string resources). */
    data class Display(val kind: Kind, val value: Int, val a: Int = 0, val b: Int = 0) {
        enum class Kind { SprintReady, Countdown, Sprinting, Rest, StartSetNow, Set }
    }

    private val _display = MutableStateFlow<Display?>(null)
    val display: StateFlow<Display?> = _display.asStateFlow()

    private fun refreshDisplay() {
        val mono = reps.monotonicNowMs
        _display.value = when (val p = _phase.value) {
            Phase.SprintReady -> Display(Display.Kind.SprintReady, ring.mode.windowSeconds ?: 60)
            is Phase.SprintCountdown -> Display(Display.Kind.Countdown, p.left)
            is Phase.Sprinting -> Display(
                Display.Kind.Sprinting,
                reps.state.value.counted - sprintStartCount,
                a = maxOf(0, ((p.endsAtMs - mono + 999) / 1000).toInt()),
                b = ring.mode.minimumReps ?: 0,
            )
            is Phase.Rest -> {
                val restLeft = maxOf(0, ((p.endsAtMs - mono + 999) / 1000).toInt())
                if (restLeft > 0) {
                    Display(Display.Kind.Rest, restLeft, a = setIndex + 2, b = ring.mode.sets ?: 1)
                } else {
                    Display(Display.Kind.StartSetNow, maxOf(0, ((p.startByMs - mono) / 1000).toInt()), a = setIndex + 2)
                }
            }
            Phase.Counting -> if (type == ModeType.Sets) {
                val per = ring.mode.repsPerSet ?: 1
                Display(Display.Kind.Set, minOf(reps.state.value.counted - setStartCount, per), a = per, b = setIndex + 1)
            } else {
                null
            }
            Phase.Done -> null
        }
    }

    private fun finish(outcome: String) {
        if (_phase.value == Phase.Done) return
        _phase.value = Phase.Done
        reps.finish(outcome)
        val d = WakeRules.decide(ring.mode, ring.t0Instant.toEpochMilli(), reps.nowMs, provisionalSession())
        // The camera session is over: anything not succeeded now is a failure for this attempt.
        _decision.value = if (d.status == "in_progress") d.copy(status = "failed") else d
        services?.let { s ->
            val practice = ring.practice || !ring.countsForChallenge
            s.uploader.enqueue(
                reps.repLog(
                    sessionId, if (practice) "training" else "wake", s.appVersion,
                    occurrenceId = if (practice) null else ring.occurrenceId, snoozes = ring.snoozesUsed,
                    anchor = anchor, ringAtMs = ring.rangAtInstant.toEpochMilli(),
                ),
            )
        }
        onOver(_decision.value?.status == "succeeded")
    }

    /** The session in wall-clock epoch ms for the provisional decision (the server uses its own anchor). */
    fun provisionalSession(): WakeRules.Session {
        val tl = reps.timeline ?: return WakeRules.Session(reps.nowMs, reps.nowMs, outcome = reps.outcome)
        val base = tl.wallStartMs
        return WakeRules.Session(
            startedAt = base,
            endedAt = base + ((tl.monotonicEndMs ?: tl.monotonicStartMs) - tl.monotonicStartMs),
            ringAt = ring.rangAtInstant.toEpochMilli(),
            outcome = reps.outcome,
            snoozes = ring.snoozesUsed,
            reps = tl.reps.map { WakeRules.Rep(base + it.tStartMs, base + it.tEndMs, it.quality) },
            sets = tl.sets.map { WakeRules.SetSpan(base + it.startMs, base + it.endMs) },
            sprintStart = tl.sprintStartMs?.let { base + it },
        )
    }
}
