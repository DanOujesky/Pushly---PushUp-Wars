package app.pushly.feature.alarm

import android.content.Context
import android.text.format.DateFormat
import app.pushly.core.alarm.AlarmKind
import app.pushly.core.alarm.AlarmSchedule
import app.pushly.core.alarm.AlarmValidation
import app.pushly.core.alarm.ChallengeMode
import app.pushly.core.alarm.ModeType
import java.time.DayOfWeek
import java.time.Duration
import java.time.LocalTime
import java.time.format.TextStyle
import java.util.Locale

/** Clock time in the user's 12/24 h preference, split so the digits can be shown huge and "AM/PM" small. */
object TimeFormat {
    data class Parts(val main: String, val suffix: String?)

    fun parts(context: Context, t: LocalTime): Parts = if (DateFormat.is24HourFormat(context)) {
        Parts("%02d:%02d".format(t.hour, t.minute), null)
    } else {
        val h = if (t.hour % 12 == 0) 12 else t.hour % 12
        Parts("%d:%02d".format(h, t.minute), if (t.hour < 12) "AM" else "PM")
    }

    fun short(context: Context, t: LocalTime): String = parts(context, t).let { p -> listOfNotNull(p.main, p.suffix).joinToString(" ") }

    fun short(context: Context, hhmm: String?): String? = parse(hhmm)?.let { short(context, it) }

    fun parse(hhmm: String?): LocalTime? =
        if (AlarmValidation.isTime(hhmm)) LocalTime.parse(hhmm) else null

    fun hhmm(t: LocalTime): String = "%02d:%02d".format(t.hour, t.minute)

    /** "in 7 h 12 min" */
    fun until(context: Context, d: Duration): String {
        val minutes = d.toMinutes().coerceAtLeast(0)
        val h = minutes / 60
        val m = minutes % 60
        return when {
            h >= 24 -> context.getString(R.string.time_in_days, h / 24, h % 24)
            h > 0 -> context.getString(R.string.time_in_hours, h, m)
            else -> context.getString(R.string.time_in_minutes, m.coerceAtLeast(1))
        }
    }

    fun dayShort(day: DayOfWeek): String = day.getDisplayName(TextStyle.SHORT, Locale.getDefault())

    fun dayNarrow(day: DayOfWeek): String = day.getDisplayName(TextStyle.NARROW, Locale.getDefault())
}

object ModeText {
    fun name(context: Context, type: ModeType): String = context.getString(
        when (type) {
            ModeType.RingUntilDone -> R.string.mode_ring_until_done
            ModeType.BeatTheClock -> R.string.mode_beat_the_clock
            ModeType.Sprint -> R.string.mode_sprint
            ModeType.Sets -> R.string.mode_sets
            ModeType.Escalation -> R.string.mode_escalation
        },
    )

    fun description(context: Context, type: ModeType): String = context.getString(
        when (type) {
            ModeType.RingUntilDone -> R.string.mode_ring_until_done_desc
            ModeType.BeatTheClock -> R.string.mode_beat_the_clock_desc
            ModeType.Sprint -> R.string.mode_sprint_desc
            ModeType.Sets -> R.string.mode_sets_desc
            ModeType.Escalation -> R.string.mode_escalation_desc
        },
    )

    /** "Ring until done · 20 push-ups" */
    fun summary(context: Context, m: ChallengeMode): String {
        val type = m.modeType ?: return ""
        val detail = when (type) {
            ModeType.RingUntilDone, ModeType.Escalation -> context.getString(R.string.mode_detail_reps, m.targetReps ?: 0)
            ModeType.BeatTheClock -> context.getString(R.string.mode_detail_beat, m.targetReps ?: 0, m.windowSeconds ?: 0)
            ModeType.Sprint -> context.getString(R.string.mode_detail_sprint, m.minimumReps ?: 0, m.windowSeconds ?: 0)
            ModeType.Sets -> context.getString(R.string.mode_detail_sets, m.sets ?: 0, m.repsPerSet ?: 0)
        }
        return "${name(context, type)} · $detail"
    }
}

object ScheduleText {
    /** "Mon–Fri", "Every day", "Weekends", "Mon, Wed, Fri" or the one-off date. */
    fun days(context: Context, s: AlarmSchedule): String {
        if (s.kind == AlarmKind.OneOff) return s.oneOff?.substringBefore('T').orEmpty()
        val weekly = s.weekly ?: return ""
        val on = DayOfWeek.entries.filter { weekly.time(it) != null }
        return when {
            on.size == 7 -> context.getString(R.string.days_every_day)
            on == DayOfWeek.entries.take(5) -> context.getString(R.string.days_weekdays)
            on == listOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY) -> context.getString(R.string.days_weekends)
            on.isEmpty() -> context.getString(R.string.days_none)
            else -> on.joinToString(", ") { TimeFormat.dayShort(it) }
        }
    }

    /** The alarm's time if all its days share one time, else null ("different times"). */
    fun singleTime(s: AlarmSchedule): String? {
        if (s.kind == AlarmKind.OneOff) return s.oneOff?.substringAfter('T')
        val times = DayOfWeek.entries.mapNotNull { s.weekly?.time(it) }.distinct()
        return times.singleOrNull()
    }
}
