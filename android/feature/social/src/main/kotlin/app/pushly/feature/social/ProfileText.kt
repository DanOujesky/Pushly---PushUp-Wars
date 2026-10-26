package app.pushly.feature.social

import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/** Profile texts (D-080). Same as iOS `ProfileText`. */
object ProfileText {
    private val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

    fun league(l: UserProfile.League): String = l.league.replaceFirstChar { it.uppercase() } + (l.tier?.let { " $it" } ?: "")

    /** "Oct 2026" from "2026-10". */
    fun since(ym: String): String {
        val parts = ym.split("-")
        val y = parts.getOrNull(0)?.toIntOrNull()
        val m = parts.getOrNull(1)?.toIntOrNull()
        if (parts.size != 2 || y == null || m == null || m !in 1..12) return ym
        return "${months[m - 1]} $y"
    }

    /** Weekday letters for the last 7 days, today last. */
    fun lastWeekLetters(today: LocalDate = LocalDate.now()): List<String> =
        (6 downTo 0).map { today.minusDays(it.toLong()).dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()) }

    /** Regional-indicator flag for a two-letter country code. */
    fun flag(code: String): String? {
        if (code.length != 2 || !code.all { it.isLetter() }) return null
        return code.uppercase().map { String(Character.toChars(0x1F1E6 + (it - 'A'))) }.joinToString("")
    }
}
