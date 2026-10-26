package app.pushly.feature.alarm

import app.pushly.core.alarm.WakeSummary
import java.time.LocalDate

/** Wake tab rules (D-079) — same as iOS `WakeGreeting`, `WakeCountdown`, `WakeWeek`. */
object WakeTabRules {
    /** morning 5–11, afternoon 12–17, evening 18–22, night otherwise. */
    fun greetingBucket(hour: Int): String = when (hour) {
        in 5..11 -> "morning"
        in 12..17 -> "afternoon"
        in 18..22 -> "evening"
        else -> "night"
    }

    /** 0 a day or more before the alarm → 1 when it rings. */
    fun countdownFraction(secondsLeft: Long): Float = (1f - secondsLeft / 86_400f).coerceIn(0f, 1f)

    /** Monday..Sunday (local) of the summary's today. */
    fun weekDates(summary: WakeSummary): List<String> {
        val today = runCatching { LocalDate.parse(summary.today) }.getOrNull() ?: return emptyList()
        val monday = today.minusDays((today.dayOfWeek.value - 1).toLong())
        return (0 until 7).map { monday.plusDays(it.toLong()).toString() }
    }

    /** Challenges beaten this week. */
    fun beaten(summary: WakeSummary): Int {
        val week = weekDates(summary).toSet()
        return summary.attempts.count { it.localDate in week && it.status == "succeeded" }
    }

    /** Challenges decided this week (beaten, failed or missed). */
    fun challenges(summary: WakeSummary): Int {
        val week = weekDates(summary).toSet()
        return summary.attempts.count { it.localDate in week && it.status in setOf("succeeded", "failed", "missed") }
    }
}
