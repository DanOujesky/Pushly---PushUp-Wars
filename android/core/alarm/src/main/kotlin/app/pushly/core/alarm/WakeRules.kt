package app.pushly.core.alarm

import kotlinx.serialization.Serializable

/**
 * Wake Challenge decision rules (doc 04 §3, doc 08 §3) — the app's provisional copy of what the server decides.
 * Port of tools/reference/pushly_ref/wake.py; tested against shared/test-vectors/wake (same as iOS + SQL).
 * All times are epoch milliseconds.
 */
object WakeRules {
    const val DEADLINE_MS: Long = 30 * 60_000L
    const val CLOCK_TOLERANCE_MS: Long = 30_000L
    const val SET_START_GRACE_S: Long = 30L

    @Serializable data class Rep(val tStart: Long, val tEnd: Long, val quality: Int)

    @Serializable data class SetSpan(val start: Long, val end: Long)

    @Serializable data class Session(
        val startedAt: Long,
        val endedAt: Long,
        val ringAt: Long? = null,
        /** completed | gaveUp | expired */
        val outcome: String = "completed",
        val snoozes: Int = 0,
        val reps: List<Rep> = emptyList(),
        val sets: List<SetSpan> = emptyList(),
        val sprintStart: Long? = null,
    )

    @Serializable data class Decision(
        /** succeeded | in_progress | failed | missed */
        val status: String,
        val finalTargetReps: Int,
        val successAt: Long?,
        val score: Int,
        val reason: String,
        val snoozesUsed: Int,
    )

    fun finalTarget(mode: ChallengeMode, snoozes: Int): Int = when (mode.modeType) {
        ModeType.Sprint -> mode.minimumReps ?: 0
        ModeType.Sets -> (mode.sets ?: 0) * (mode.repsPerSet ?: 0)
        ModeType.Escalation -> (mode.targetReps ?: 0) + minOf(snoozes, mode.maxSnoozes ?: 0) * (mode.snoozeAddsReps ?: 0)
        else -> mode.targetReps ?: 0
    }

    fun decide(mode: ChallengeMode, t0: Long, now: Long, s: Session): Decision {
        val deadline = t0 + DEADLINE_MS
        val type = mode.modeType
        val snoozes = if (type == ModeType.Escalation) minOf(s.snoozes, mode.maxSnoozes ?: 0) else 0
        val target = finalTarget(mode, snoozes)
        val reps = s.reps.filter { it.tStart >= t0 - CLOCK_TOLERANCE_MS && it.tEnd <= deadline }
            .sortedWith(compareBy<Rep>({ it.tEnd }, { it.tStart }))
        var successAt: Long? = null
        var score = reps.size
        var reason = "not_reached"

        if (s.startedAt > deadline) {
            reason = "started_after_deadline"
        } else {
            when (type) {
                ModeType.BeatTheClock -> {
                    val start = s.ringAt?.let { maxOf(t0, minOf(it, deadline)) } ?: t0
                    val inside = reps.filter { it.tEnd <= start + (mode.windowSeconds ?: 0) * 1000L }
                    score = inside.size
                    if (target > 0 && inside.size >= target) successAt = inside[target - 1].tEnd
                    else if (reps.size >= target) reason = "window_expired"
                }
                ModeType.Sprint -> {
                    val start = s.sprintStart
                    if (start == null) {
                        reason = "sprint_not_started"
                    } else if (start > deadline || start < t0 - CLOCK_TOLERANCE_MS) {
                        reason = "sprint_outside_deadline"
                    } else {
                        val end = start + (mode.windowSeconds ?: 0) * 1000L
                        val inside = reps.filter { it.tStart >= start && it.tEnd <= end }
                        score = inside.size
                        val minimum = mode.minimumReps ?: 0
                        if (minimum > 0 && inside.size >= minimum) successAt = inside[minimum - 1].tEnd
                        else if (s.endedAt >= end || now >= end) reason = "sprint_too_few"
                    }
                }
                ModeType.Sets -> {
                    var done = 0
                    var prevEnd: Long? = null
                    val rest = (mode.restSeconds ?: 0).toLong()
                    for (set in s.sets.sortedBy { it.start }) {
                        val p = prevEnd
                        if (p != null && set.start > p + (rest + SET_START_GRACE_S) * 1000L) {
                            reason = "rest_too_long"
                            break
                        }
                        val n = reps.count { it.tStart >= set.start && it.tEnd <= set.end }
                        if (n < (mode.repsPerSet ?: 0)) break
                        done++
                        prevEnd = set.end
                        if (done == (mode.sets ?: 0)) {
                            successAt = set.end
                            break
                        }
                    }
                    score = done
                }
                else -> if (target > 0 && reps.size >= target) successAt = reps[target - 1].tEnd
            }
        }

        var status = when {
            successAt != null -> "succeeded".also { reason = "ok" }
            s.outcome == "gaveUp" || now > deadline ||
                reason in setOf("window_expired", "sprint_too_few", "rest_too_long", "sprint_outside_deadline") -> "failed"
            else -> "in_progress"
        }
        if (reason == "started_after_deadline") status = "missed"
        return Decision(status, target, successAt, score, reason, snoozes)
    }

    /** Wake Score of a succeeded attempt (doc 08 §3, integer math). */
    fun points(finalTargetReps: Int, mode: String, snoozesUsed: Int, avgQuality: Int): Int {
        val difficulty = minOf(20, finalTargetReps / 5)
        val bonus = when (ModeType.fromWire(mode)) {
            ModeType.BeatTheClock, ModeType.Sprint, ModeType.Sets -> 3
            ModeType.Escalation -> -2 * snoozesUsed
            else -> 0
        }
        val quality = if (avgQuality >= 90) 3 else if (avgQuality >= 75) 1 else 0
        return maxOf(5, 10 + difficulty + bonus + quality)
    }
}
