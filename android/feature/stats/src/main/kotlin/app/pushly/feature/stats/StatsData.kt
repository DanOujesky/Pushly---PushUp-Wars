package app.pushly.feature.stats

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** `get_stats(period)` (shared/contracts/stats.schema.json). Personal stats use the user's local days. Same as iOS. */
@Serializable
data class StatsData(
    val period: String,
    val from: String,
    val to: String,
    val kpis: Kpis,
    val daily: List<Day>,
    val cumulativeBefore: Int,
    val wakes: List<Wake>,
    val heatmap: List<HeatDay>,
    val records: Records,
    val progress: Level,
    val achievements: AchievementCount,
) {
    @Serializable data class Kpis(
        val reps: Int,
        val repsPrev: Int,
        val bestSet: Int,
        val bestSetPrev: Int,
        val wakeSuccessPct: Int? = null,
        val wakeSuccessPctPrev: Int? = null,
        val avgQuality: Int? = null,
        val avgQualityPrev: Int? = null,
    )

    @Serializable data class Day(
        val date: String,
        val wake: Int,
        val battle: Int,
        val training: Int,
        val total: Int,
        val bestSet: Int,
        val avgQuality: Int? = null,
    )

    @Serializable data class Wake(
        val date: String,
        val status: String,
        val scheduledAt: String? = null,
        val completedAt: String? = null,
        val scheduledMinute: Double? = null,
        val completedMinute: Double? = null,
    )

    @Serializable data class HeatDay(val date: String, val reps: Int)

    @Serializable data class Records(val bestSet: Int, val maxDay: Int, val bestStreak: Int, val repsAllTime: Int)

    @Serializable data class Level(val level: Int, val xpIntoLevel: Int, val xpForNext: Int, val xp: Int) {
        val fraction: Float get() = if (xpForNext > 0) xpIntoLevel.toFloat() / xpForNext else 1f
    }

    @Serializable data class AchievementCount(val unlocked: Int, val total: Int)

    enum class Period(val wire: String) { Week("week"), Month("month"), Year("year"), All("all") }

    companion object {
        val JSON = Json { ignoreUnknownKeys = true }
        fun decode(json: String): StatsData = JSON.decodeFromString(serializer(), json)
    }
}

/** One row of `get_achievements()` (shared/contracts/achievements.schema.json). [icon] is an SF Symbol name. */
@Serializable
data class AchievementItem(
    val id: String,
    val group: String,
    val title: String,
    val description: String,
    val icon: String,
    val tier: Int,
    val xp: Int,
    val unlockedAt: String? = null,
) {
    val unlocked: Boolean get() = unlockedAt != null

    companion object {
        fun decodeList(json: String): List<AchievementItem> =
            StatsData.JSON.decodeFromString(kotlinx.serialization.builtins.ListSerializer(serializer()), json)
    }
}
