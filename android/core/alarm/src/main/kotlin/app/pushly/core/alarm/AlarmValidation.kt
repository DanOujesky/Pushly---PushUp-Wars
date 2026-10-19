package app.pushly.core.alarm

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit

/**
 * AlarmSchedule rules (doc 04 §2), enforced in the editor and on the server. Returns error codes (contract:
 * shared/test-vectors/alarm-validation/cases.json); an empty set means valid. Mirrors tools/reference/pushly_ref/validation.py.
 */
object AlarmValidation {
    private val TIME = Regex("^([01]\\d|2[0-3]):([0-5]\\d)$")

    fun isTime(value: String?): Boolean = value != null && TIME.matches(value)

    fun errors(s: AlarmSchedule, today: LocalDate): Set<String> {
        val e = linkedSetOf<String>()
        when (s.kind) {
            AlarmKind.Weekly -> weekly(s, today, e)
            AlarmKind.OneOff -> if (parseLocalDateTime(s.oneOff) == null) e += "oneOff.invalid"
        }
        s.pause?.let { p ->
            val from = parseDate(p.from)
            val to = parseDate(p.to)
            when {
                from == null || to == null -> e += "pause.invalid"
                to < from -> e += "pause.order"
                ChronoUnit.DAYS.between(from, to) + 1 > 30 -> e += "pause.tooLong"
            }
        }
        mode(s.mode, e)
        return e
    }

    private fun weekly(s: AlarmSchedule, today: LocalDate, e: MutableSet<String>) {
        val weekly = s.weekly ?: WeeklyTimes()
        for ((name, value) in listOf("mon" to weekly.mon, "tue" to weekly.tue, "wed" to weekly.wed, "thu" to weekly.thu,
            "fri" to weekly.fri, "sat" to weekly.sat, "sun" to weekly.sun)) {
            if (value != null && !isTime(value)) e += "weekly.$name.time"
        }
        if (weekly.isEmpty && s.overrides.isEmpty()) e += "weekly.empty"
        if (s.overrides.size > 60) e += "overrides.tooMany"
        val seen = HashSet<LocalDate>()
        for (ov in s.overrides) {
            val d = parseDate(ov.date)
            if (d == null) {
                e += "overrides.date"
                continue
            }
            if (d < today) e += "overrides.past"
            if (!seen.add(d)) e += "overrides.duplicate"
            if (ov.skip != true && !isTime(ov.time)) e += "overrides.time"
        }
    }

    private fun mode(m: ChallengeMode, e: MutableSet<String>) {
        fun inRange(v: Int?, lo: Int, hi: Int) = v != null && v in lo..hi
        val t = m.modeType
        if (t == ModeType.RingUntilDone || t == ModeType.BeatTheClock || t == ModeType.Escalation) {
            if (!inRange(m.targetReps, 5, 100)) e += "mode.targetReps"
        }
        if (t == ModeType.BeatTheClock && !inRange(m.windowSeconds, 30, 600)) e += "mode.windowSeconds"
        if (t == ModeType.Sprint) {
            if (m.windowSeconds !in setOf(30, 60, 120)) e += "mode.windowSeconds"
            if (!inRange(m.minimumReps, 5, 100)) e += "mode.minimumReps"
        }
        if (t == ModeType.Sets) {
            if (!inRange(m.sets, 2, 5)) e += "mode.sets"
            if (!inRange(m.repsPerSet, 5, 50)) e += "mode.repsPerSet"
            if (!inRange(m.restSeconds, 15, 180)) e += "mode.restSeconds"
        }
        if (t == ModeType.Escalation) {
            if (!inRange(m.snoozeAddsReps, 1, 20)) e += "mode.snoozeAddsReps"
            if (!inRange(m.snoozeMinutes, 1, 10)) e += "mode.snoozeMinutes"
            if (!inRange(m.maxSnoozes, 1, 5)) e += "mode.maxSnoozes"
        }
        if (t == null) e += "mode.type"
    }

    /** True when beat-the-clock leaves under 3 s per push-up (editor warning, doc 04 §3). */
    fun isVeryHard(m: ChallengeMode): Boolean {
        val target = m.targetReps ?: return false
        val window = m.windowSeconds ?: return false
        return m.modeType == ModeType.BeatTheClock && target > 0 && window.toDouble() / target < 3.0
    }

    internal fun parseDate(value: String?): LocalDate? = try {
        value?.let(LocalDate::parse)
    } catch (_: DateTimeParseException) {
        null
    }

    internal fun parseLocalDateTime(value: String?): LocalDateTime? = try {
        value?.let(LocalDateTime::parse)
    } catch (_: DateTimeParseException) {
        null
    }
}
