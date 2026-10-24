package app.pushly.feature.wakeflow

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Drives one workout (D-069), same as iOS `WorkoutSessionModel`: the camera counts, [WorkoutRunner] turns push-ups
 * into sets and rest, this class turns runner events into cues, set markers for the rep log and the counter display.
 * Main thread only (rep callbacks and ticks both arrive there).
 */
class WorkoutSession(
    val workout: Workout,
    private val context: Context,
    val reps: RepSessionModel = RepSessionModel(RepSessionModel.Mode.Training),
    private val sounds: RepSounds? = RepSounds(context),
) {
    val runner = WorkoutRunner(workout)
    private val _snapshot = MutableStateFlow(runner.snapshot(reps.monotonicNowMs))

    /** Changes on every runner input — the screen redraws its controls from it. */
    val snapshot: StateFlow<WorkoutRunner.Snapshot> = _snapshot.asStateFlow()
    private val _completed = MutableStateFlow(false)
    val completed: StateFlow<Boolean> = _completed.asStateFlow()
    private var seen = 0
    private var lastBeep = -1L

    init {
        reps.onCounted = { total -> counted(total) }
        refreshDisplay()
    }

    private val now get() = reps.monotonicNowMs

    /** Sets start once the user is in position (the camera sees a plank) — not while the phone is being propped up. */
    fun inPosition() {
        if (runner.phase == WorkoutRunner.Phase.Ready) step { it.start(now) }
    }

    fun tick() = step { it.tick(now) }
    fun endSet() = step { it.endSet(now) }
    fun skipRest() = step { it.skipRest(now) }
    fun finish() = step { it.finish(now) }

    fun release() {
        sounds?.release()
    }

    private fun counted(total: Int) {
        while (seen < total) {
            seen += 1
            step { it.rep(now) }
            // per-set count; the last rep of a set is followed by the rest call instead
            if (runner.phase == WorkoutRunner.Phase.Set && runner.setReps > 0 && sounds?.voice == true) {
                sounds.announce(runner.setReps.toString())
            }
        }
    }

    private fun step(change: (WorkoutRunner) -> Unit) {
        if (_completed.value) return
        val before = runner.events.size
        change(runner)
        runner.events.drop(before).forEach { react(it) }
        if (runner.phase == WorkoutRunner.Phase.Rest) restBeeps()
        refreshDisplay()
    }

    private fun react(event: WorkoutRunner.Event) {
        when (event) {
            is WorkoutRunner.Event.SetStarted -> {
                reps.markSetStart()
                sounds?.play(RepSounds.Effect.Go)
                sounds?.announce(setCall(event.set + 1, workout.sets.size, workout.sets[event.set]))
            }
            is WorkoutRunner.Event.SetEnded -> {
                reps.markSetEnd()
                sounds?.play(RepSounds.Effect.Done)
            }
            is WorkoutRunner.Event.RestStarted ->
                sounds?.announce(context.getString(R.string.workout_call_rest, ((event.until - event.t + 999) / 1000).toInt()))
            is WorkoutRunner.Event.Done -> {
                _completed.value = true
                reps.finish()
            }
        }
    }

    private fun restBeeps() {
        val left = runner.snapshot(now).msLeft ?: return
        val second = (left + 999) / 1000
        if (second in 1..3 && second != lastBeep) {
            lastBeep = second
            sounds?.play(RepSounds.Effect.Count)
        }
    }

    private fun setCall(n: Int, total: Int, s: WorkoutSet): String =
        if (n == total) context.getString(R.string.workout_call_last, setLabel(context, s))
        else context.getString(R.string.workout_call_set, n, setLabel(context, s))

    private fun refreshDisplay() {
        val snap = runner.snapshot(now)
        _snapshot.value = snap
        val count = workout.sets.size
        reps.setDisplay(
            when (snap.phase) {
                WorkoutRunner.Phase.Ready -> RepSessionModel.CounterDisplay("0", context.getString(R.string.workout_get_ready))
                WorkoutRunner.Phase.Set -> {
                    val s = runner.currentSet
                    var caption = context.getString(R.string.workout_set_of, snap.index + 1, count)
                    var progress: Float? = null
                    when (s.kind) {
                        SetKind.REPS -> {
                            caption += " · " + context.getString(R.string.workout_goal, s.target)
                            progress = snap.setReps / maxOf(s.target, 1).toFloat()
                        }
                        SetKind.TIMED -> progress = snap.msLeft?.let { 1f - it / (maxOf(s.target, 1) * 1000f) }
                        SetKind.AMRAP -> caption += " · " + context.getString(R.string.workout_amrap_caption)
                    }
                    snap.msLeft?.let { caption += " · " + clock(it) }
                    RepSessionModel.CounterDisplay(snap.setReps.toString(), caption, progress)
                }
                WorkoutRunner.Phase.Rest -> {
                    val next = workout.sets[minOf(snap.index, count - 1)]
                    RepSessionModel.CounterDisplay(
                        clock(snap.msLeft ?: 0),
                        context.getString(R.string.workout_rest_next, setLabel(context, next)),
                    )
                }
                WorkoutRunner.Phase.Done ->
                    RepSessionModel.CounterDisplay(snap.total.toString(), context.getString(R.string.workout_done), 1f)
            },
        )
    }

    companion object {
        fun clock(ms: Long): String {
            val s = ((ms + 999) / 1000).toInt()
            return "%d:%02d".format(s / 60, s % 60)
        }

        fun setLabel(context: Context, s: WorkoutSet): String = when (s.kind) {
            SetKind.REPS -> context.getString(R.string.workout_pushups, s.target)
            SetKind.AMRAP -> context.getString(R.string.workout_label_max)
            SetKind.TIMED -> context.getString(R.string.workout_target_timed, s.target)
        }

        fun duration(context: Context, seconds: Int): String =
            if (seconds < 60) context.getString(R.string.workout_seconds, seconds)
            else context.getString(R.string.workout_minutes, maxOf(1, (seconds + 30) / 60))
    }
}
