package app.pushly.core.designsystem

/**
 * Achievement icons are SF Symbol names (shared/achievements/definitions.json, iOS draws them directly). Android shows
 * a glyph instead (D-049): the number for numbered symbols ("25.circle" → "25"), otherwise a matching emoji.
 */
fun achievementGlyph(icon: String): String {
    icon.substringBefore('.').toIntOrNull()?.let { return it.toString() }
    return when (icon.substringBefore('.')) {
        "sunrise", "sun" -> "☀️"
        "bird" -> "🐦"
        "moon" -> "🌙"
        "bolt" -> "⚡"
        "calendar" -> "📅"
        "checkmark" -> "✔️"
        "crown" -> "👑"
        "envelope" -> "✉️"
        "figure" -> "💪"
        "flag" -> "🏁"
        "flame" -> "🔥"
        "graduationcap" -> "🎓"
        "medal" -> "🏅"
        "person" -> "👥"
        "shield" -> "🛡️"
        "sparkles" -> "✨"
        "square" -> "▦"
        "timer" -> "⏱️"
        else -> "★"
    }
}
