package app.pushly.core.alarm

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId

/** One concrete ring of an alarm on a local date (doc 04 §1). */
data class Occurrence(
    val occurrenceId: String,
    val alarmId: String,
    val localDate: LocalDate,
    val instant: Instant,
    val countsForChallenge: Boolean,
)

/**
 * Pure occurrence computation (doc 04 §4) — same results as iOS `AlarmOccurrences` and
 * tools/reference/pushly_ref/occurrences.py for every vector in shared/test-vectors/alarm-occurrences.
 */
object AlarmOccurrences {
    private const val MAX_GAP_MINUTES = 180L

    /** Wall-clock time the alarm rings on local date [d], or null. No time zones involved. */
    fun localTimeFor(s: AlarmSchedule, d: LocalDate): LocalTime? {
        if (!s.enabled) return null
        s.pause?.let { p ->
            val from = AlarmValidation.parseDate(p.from)
            val to = AlarmValidation.parseDate(p.to)
            if (from != null && to != null && d >= from && d <= to) return null
        }
        return when (s.kind) {
            AlarmKind.OneOff -> AlarmValidation.parseLocalDateTime(s.oneOff)?.takeIf { it.toLocalDate() == d }?.toLocalTime()
            AlarmKind.Weekly -> {
                val override = s.overrides.firstOrNull { it.date == d.toString() }
                if (override != null) {
                    if (override.skip == true) null else parseTime(override.time)
                } else {
                    parseTime(s.weekly?.time(d.dayOfWeek))
                }
            }
        }
    }

    /** Local date+time → instant: DST gap → first valid minute after it; overlap → first (earlier) instance. */
    fun resolveLocal(d: LocalDate, t: LocalTime, zone: ZoneId): Instant {
        val rules = zone.rules
        val naive = LocalDateTime.of(d, t)
        for (minutes in 0..MAX_GAP_MINUTES) {
            val candidate = naive.plusMinutes(minutes)
            val offsets = rules.getValidOffsets(candidate)
            if (offsets.isNotEmpty()) return offsets.minOf { candidate.toInstant(it) }
        }
        error("could not resolve $naive in $zone")
    }

    /** Occurrences of one alarm for local dates [today, today + horizonDays], strictly after [from], sorted. */
    fun occurrences(s: AlarmSchedule, from: Instant, zone: ZoneId, horizonDays: Int): List<Occurrence> {
        val today = from.atZone(zone).toLocalDate()
        val out = ArrayList<Occurrence>()
        for (offset in 0..horizonDays) {
            val d = today.plusDays(offset.toLong())
            val t = localTimeFor(s, d) ?: continue
            val instant = resolveLocal(d, t, zone)
            if (!instant.isAfter(from)) continue
            out += Occurrence("${s.id}:$d", s.id, d, instant, s.countsForChallenge)
        }
        return out.sortedWith(ORDER)
    }

    fun all(schedules: List<AlarmSchedule>, from: Instant, zone: ZoneId, horizonDays: Int): List<Occurrence> =
        schedules.flatMap { occurrences(it, from, zone, horizonDays) }.sortedWith(ORDER)

    /** The one occurrence that counts for the Wake Challenge on [date]: earliest challenge alarm, ties by alarm id. */
    fun challengeOccurrence(date: LocalDate, occurrences: List<Occurrence>): Occurrence? =
        occurrences.filter { it.localDate == date && it.countsForChallenge }.minWithOrNull(ORDER)

    /** Next ring of [s] (looks ahead far enough for one-off alarms, overrides and pauses). */
    fun next(s: AlarmSchedule, from: Instant, zone: ZoneId): Occurrence? =
        occurrences(s, from, zone, AlarmPlan.ANDROID_LOOKAHEAD_DAYS).firstOrNull()

    private val ORDER = compareBy<Occurrence>({ it.instant }, { it.alarmId })

    private fun parseTime(value: String?): LocalTime? {
        if (!AlarmValidation.isTime(value)) return null
        val v = value ?: return null
        return LocalTime.of(v.substring(0, 2).toInt(), v.substring(3, 5).toInt())
    }

    /** Completion deadline of every mode: T0 + 30 min (doc 04 §3). */
    val DEADLINE: Duration = Duration.ofMinutes(30)
}
