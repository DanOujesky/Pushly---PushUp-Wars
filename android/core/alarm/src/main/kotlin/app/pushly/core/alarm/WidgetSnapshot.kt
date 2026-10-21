package app.pushly.core.alarm

import java.time.Instant
import java.time.ZoneId

/**
 * What the home screen widget shows (P6-07). Same fields and rules as iOS `WidgetSnapshot`: upcoming rings from the
 * local schedules (soonest first, at most 8 within 7 days) + the last known streak and push-ups today.
 */
data class WidgetSnapshot(
    val upcoming: List<Upcoming>,
    val streak: Int?,
    val repsToday: Int?,
    val today: String?,
) {
    data class Upcoming(val at: Instant, val label: String, val targetReps: Int?, val countsForChallenge: Boolean)

    /** The ring to show at [date] (the first one still ahead). */
    fun next(after: Instant): Upcoming? = upcoming.firstOrNull { it.at.isAfter(after) }

    /** Push-ups today only while it is still that local day. */
    fun repsToday(at: Instant, zone: ZoneId): Int? = if (today != null && today == at.atZone(zone).toLocalDate().toString()) repsToday else null

    companion object {
        const val MAX_UPCOMING = 8

        fun upcoming(schedules: List<AlarmSchedule>, from: Instant, zone: ZoneId): List<Upcoming> {
            val byId = schedules.associateBy { it.id }
            return AlarmOccurrences.all(schedules.filter { it.enabled }, from, zone, 7)
                .filter { it.instant.isAfter(from) }
                .sortedBy { it.instant }
                .take(MAX_UPCOMING)
                .map { o ->
                    val s = byId[o.alarmId]
                    Upcoming(o.instant, s?.label.orEmpty(), s?.mode?.targetReps, o.countsForChallenge)
                }
        }
    }
}
