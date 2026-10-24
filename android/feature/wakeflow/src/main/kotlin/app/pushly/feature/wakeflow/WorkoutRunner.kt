package app.pushly.feature.wakeflow

/**
 * Workout runner (D-069) — port of tools/reference/pushly_ref/workout.py, same as iOS `WorkoutRunner`; replays
 * shared/test-vectors/workouts/runner.json. Times are monotonic milliseconds.
 */
class WorkoutRunner(val workout: Workout) {
    enum class Phase { Ready, Set, Rest, Done }

    sealed interface Event {
        val t: Long

        data class SetStarted(val set: Int, override val t: Long) : Event
        data class SetEnded(val set: Int, val reps: Int, val completed: Boolean, override val t: Long) : Event
        data class RestStarted(val next: Int, val until: Long, override val t: Long) : Event
        data class Done(override val t: Long) : Event
    }

    data class SetResult(val reps: Int, val target: Int, val completed: Boolean)

    data class Snapshot(val phase: Phase, val index: Int, val setReps: Int, val total: Int, val msLeft: Long?)

    var phase = Phase.Ready
        private set

    /** Current set (in rest: the set that comes next). */
    var index = 0
        private set
    var setReps = 0
        private set
    var total = 0
        private set
    val results = ArrayList<SetResult>()
    val events = ArrayList<Event>()
    private var setStart = 0L
    private var restEnd = 0L
    private var lastRep: Long? = null

    private val sets get() = workout.sets
    private val everyMs: Long? get() = workout.everyS?.takeIf { it > 0 }?.let { it * 1000L }
    val currentSet: WorkoutSet get() = sets[minOf(index, sets.size - 1)]

    fun start(t: Long) {
        if (phase == Phase.Ready) startSet(0, t)
    }

    fun rep(t: Long) {
        tick(t)
        if (phase != Phase.Set && phase != Phase.Rest) return
        total += 1
        if (phase != Phase.Set) return
        setReps += 1
        lastRep = t
        val s = sets[index]
        if (s.kind == SetKind.REPS && setReps >= s.target) endCurrent(t)
    }

    fun tick(t: Long) {
        while (true) {
            when (phase) {
                Phase.Set -> {
                    val d = setDeadline() ?: return
                    if (t < d) return
                    endCurrent(d)
                }
                Phase.Rest -> {
                    if (t < restEnd) return
                    startSet(index, restEnd)
                }
                Phase.Ready, Phase.Done -> return
            }
        }
    }

    fun endSet(t: Long) {
        tick(t)
        if (phase == Phase.Set) endCurrent(t)
    }

    fun skipRest(t: Long) {
        tick(t)
        if (phase == Phase.Rest) startSet(index, t)
    }

    /** The user stops early: a running set is recorded as it is, the rest are skipped. */
    fun finish(t: Long) {
        tick(t)
        if (phase == Phase.Set) record(t)
        if (phase != Phase.Done) {
            phase = Phase.Done
            events += Event.Done(t)
        }
    }

    fun snapshot(t: Long): Snapshot {
        val left: Long? = when (phase) {
            Phase.Set -> setDeadline()?.takeIf { currentSet.kind != SetKind.AMRAP }?.let { maxOf(it - t, 0) }
            Phase.Rest -> maxOf(restEnd - t, 0)
            else -> null
        }
        return Snapshot(phase, index, setReps, total, left)
    }

    private fun setDeadline(): Long? {
        val s = sets[index]
        everyMs?.let { return setStart + it }
        if (s.kind == SetKind.TIMED) return setStart + s.target * 1000L
        if (s.kind == SetKind.AMRAP) lastRep?.let { return it + AMRAP_IDLE_MS }
        return null
    }

    private fun startSet(i: Int, t: Long) {
        phase = Phase.Set
        index = i
        setReps = 0
        setStart = t
        lastRep = null
        events += Event.SetStarted(i, t)
    }

    private fun record(t: Long) {
        val s = sets[index]
        val done = if (s.kind == SetKind.REPS) setReps >= s.target else setReps >= 1
        results += SetResult(setReps, s.target, done)
        events += Event.SetEnded(index, setReps, done, t)
    }

    private fun endCurrent(t: Long) {
        record(t)
        val next = index + 1
        if (next >= sets.size) {
            phase = Phase.Done
            events += Event.Done(t)
            return
        }
        val end = everyMs?.let { setStart + it } ?: (t + sets[index].restS * 1000L)
        if (end <= t) {
            startSet(next, t)
            return
        }
        phase = Phase.Rest
        index = next
        restEnd = end
        events += Event.RestStarted(next, end, t)
    }

    companion object {
        const val AMRAP_IDLE_MS = 6000L
    }
}
