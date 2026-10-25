package app.pushly.core.alarm

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.DayOfWeek

/** A user-defined alarm (doc 04 §2). Wire shape = shared/contracts/alarm-schedule.schema.json; same fields as iOS. */
@Serializable
data class AlarmSchedule(
    val id: String,
    val version: Int = 1,
    val label: String = "",
    val enabled: Boolean = true,
    val countsForChallenge: Boolean = true,
    val kind: AlarmKind = AlarmKind.Weekly,
    val weekly: WeeklyTimes? = null,
    /** Local date-time `yyyy-MM-ddTHH:mm`, when [kind] is one-off. */
    val oneOff: String? = null,
    val overrides: List<AlarmOverride> = emptyList(),
    val pause: AlarmPause? = null,
    val mode: ChallengeMode = ChallengeMode.default(),
    val sound: AlarmSound = AlarmSound(),
    val vibration: String? = null,
    val preAlarmMinutes: Int? = null,
    val bedtimeReminderMinutes: Int? = null,
    val updatedAt: String? = null,
) {
    companion object {
        const val MAX_ALARMS_PER_USER = 20
        const val MAX_LABEL_LENGTH = 40

        /** New alarm as the editor opens it: weekdays 06:30, ring until 20 push-ups. */
        fun newDefault(id: String): AlarmSchedule = AlarmSchedule(
            id = id,
            label = "",
            weekly = WeeklyTimes(mon = "06:30", tue = "06:30", wed = "06:30", thu = "06:30", fri = "06:30"),
        )
    }
}

@Serializable
enum class AlarmKind {
    @SerialName("weekly") Weekly,

    @SerialName("oneOff") OneOff,
}

/** Wall-clock time per weekday (`HH:mm`), null = no alarm that day. */
@Serializable
data class WeeklyTimes(
    val mon: String? = null,
    val tue: String? = null,
    val wed: String? = null,
    val thu: String? = null,
    val fri: String? = null,
    val sat: String? = null,
    val sun: String? = null,
) {
    fun time(day: DayOfWeek): String? = when (day) {
        DayOfWeek.MONDAY -> mon
        DayOfWeek.TUESDAY -> tue
        DayOfWeek.WEDNESDAY -> wed
        DayOfWeek.THURSDAY -> thu
        DayOfWeek.FRIDAY -> fri
        DayOfWeek.SATURDAY -> sat
        DayOfWeek.SUNDAY -> sun
    }

    fun with(day: DayOfWeek, time: String?): WeeklyTimes = when (day) {
        DayOfWeek.MONDAY -> copy(mon = time)
        DayOfWeek.TUESDAY -> copy(tue = time)
        DayOfWeek.WEDNESDAY -> copy(wed = time)
        DayOfWeek.THURSDAY -> copy(thu = time)
        DayOfWeek.FRIDAY -> copy(fri = time)
        DayOfWeek.SATURDAY -> copy(sat = time)
        DayOfWeek.SUNDAY -> copy(sun = time)
    }

    val isEmpty: Boolean get() = DayOfWeek.entries.all { time(it) == null }
}

/** A date-specific change: another time, or `skip` = no alarm that day. */
@Serializable
data class AlarmOverride(val date: String, val time: String? = null, val skip: Boolean? = null)

@Serializable
data class AlarmPause(val from: String, val to: String)

/** The 5 challenge modes (doc 04 §3). [type] stays a string so unknown values from newer clients survive a round trip. */
@Serializable
data class ChallengeMode(
    val type: String,
    val targetReps: Int? = null,
    val windowSeconds: Int? = null,
    val minimumReps: Int? = null,
    val sets: Int? = null,
    val repsPerSet: Int? = null,
    val restSeconds: Int? = null,
    val snoozeAddsReps: Int? = null,
    val snoozeMinutes: Int? = null,
    val maxSnoozes: Int? = null,
) {
    val modeType: ModeType? get() = ModeType.fromWire(type)

    /** Push-ups needed without snoozes (sets: all sets together). */
    val totalReps: Int
        get() = when (modeType) {
            ModeType.Sets -> (sets ?: 0) * (repsPerSet ?: 0)
            ModeType.Sprint -> minimumReps ?: 0
            else -> targetReps ?: 0
        }

    companion object {
        fun default() = ChallengeMode(type = ModeType.RingUntilDone.wire, targetReps = 20)

        /** Sensible starting values when the user switches mode in the editor (all valid per doc 04 §2). */
        fun defaults(type: ModeType, targetReps: Int = 20): ChallengeMode = when (type) {
            ModeType.RingUntilDone -> ChallengeMode(type.wire, targetReps = targetReps)
            ModeType.BeatTheClock -> ChallengeMode(type.wire, targetReps = targetReps.coerceIn(5, 100), windowSeconds = 120)
            ModeType.Sprint -> ChallengeMode(type.wire, windowSeconds = 60, minimumReps = 15)
            ModeType.Sets -> ChallengeMode(type.wire, sets = 3, repsPerSet = 10, restSeconds = 45)
            ModeType.Escalation -> ChallengeMode(type.wire, targetReps = targetReps, snoozeAddsReps = 5, snoozeMinutes = 5, maxSnoozes = 3)
        }
    }
}

enum class ModeType(val wire: String) {
    RingUntilDone("ringUntilDone"),
    BeatTheClock("beatTheClock"),
    Sprint("sprint"),
    Sets("sets"),
    Escalation("escalation"),
    ;

    companion object {
        fun fromWire(value: String): ModeType? = entries.firstOrNull { it.wire == value }
    }
}

@Serializable
data class AlarmSound(val id: String = AlarmSounds.DEFAULT_ID, val rampSeconds: Int? = null)

/** Sounds shipped in the app (original synthesized tones until the licensed pack arrives — decisions log Q-02). */
object AlarmSounds {
    const val DEFAULT_ID = "bundled.pulse"
    val bundled: List<String> = listOf(
        "bundled.pulse", "bundled.rise", "bundled.arena", "bundled.classic",
        "bundled.thunder", "bundled.anthem", "bundled.drill", "bundled.sunrise",
    )

    /**
     * Pro sound pack (D-074, shared/cosmetics/cosmetics.json). Picking one needs Pro; an alarm that already uses one keeps
     * ringing it after Pro ends — the alarm must never break over a subscription (CLAUDE.md §4.4).
     */
    val pro: Set<String> = setOf("bundled.thunder", "bundled.anthem", "bundled.drill", "bundled.sunrise")

    /** File name (without extension) of a bundled sound; unknown ids fall back to the default (doc 04 §8). */
    fun resourceName(id: String): String = (if (id in bundled) id else DEFAULT_ID).removePrefix("bundled.")
}
