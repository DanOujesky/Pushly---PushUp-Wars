package app.pushly.core.alarm

import kotlinx.serialization.Serializable
import java.time.Duration
import java.time.Instant

/**
 * An occurrence that is ringing or waiting for its push-ups (doc 04 §3, §7). Pure rules; persisted in
 * [AlarmDocument.active] so a killed app can resume the challenge. Same rules as iOS `RingState`.
 */
@Serializable
data class RingState(
    val occurrenceId: String,
    val alarmId: String,
    val label: String,
    /** Scheduled ring time T0 (ISO instant). */
    val t0: String,
    /** When the phone actually rang (ISO instant); differs from T0 if the OS delivered late. */
    val rangAt: String,
    val mode: ChallengeMode,
    val countsForChallenge: Boolean,
    val practice: Boolean = false,
    val snoozesUsed: Int = 0,
    /** While snoozed (escalation only): ISO instant the alarm rings again. */
    val snoozedUntil: String? = null,
    val soundId: String = AlarmSounds.DEFAULT_ID,
) {
    val t0Instant: Instant get() = Instant.parse(t0)
    val rangAtInstant: Instant get() = Instant.parse(rangAt)

    /** Completion deadline: T0 + 30 min for every mode. */
    val deadline: Instant get() = t0Instant.plus(AlarmOccurrences.DEADLINE)

    /** Push-ups needed now: escalation adds `snoozeAddsReps` per snooze. */
    val target: Int
        get() = if (mode.modeType == ModeType.Escalation) {
            (mode.targetReps ?: 0) + snoozesUsed * (mode.snoozeAddsReps ?: 0)
        } else {
            mode.totalReps
        }

    val canSnooze: Boolean get() = mode.modeType == ModeType.Escalation && snoozesUsed < (mode.maxSnoozes ?: 0)

    /** Beat the clock: the window starts at T0, or at the actual ring time if the OS rang late. */
    val beatTheClockEndsAt: Instant?
        get() {
            if (mode.modeType != ModeType.BeatTheClock) return null
            val start = if (rangAtInstant.isAfter(t0Instant)) rangAtInstant else t0Instant
            return start.plusSeconds((mode.windowSeconds ?: 0).toLong())
        }

    fun snoozed(at: Instant): RingState {
        val minutes = (mode.snoozeMinutes ?: 5).toLong()
        return copy(snoozesUsed = snoozesUsed + 1, snoozedUntil = at.plus(Duration.ofMinutes(minutes)).toString())
    }

    fun isExpired(at: Instant): Boolean = !deadline.isAfter(at)

    companion object {
        fun start(occurrence: Occurrence, schedule: AlarmSchedule, rangAt: Instant, practice: Boolean = false) = RingState(
            occurrenceId = occurrence.occurrenceId,
            alarmId = schedule.id,
            label = schedule.label,
            t0 = occurrence.instant.toString(),
            rangAt = rangAt.toString(),
            mode = schedule.mode,
            countsForChallenge = occurrence.countsForChallenge && !practice,
            practice = practice,
            soundId = schedule.sound.id,
        )
    }
}
