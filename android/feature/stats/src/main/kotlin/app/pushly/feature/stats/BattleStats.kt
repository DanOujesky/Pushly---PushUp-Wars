package app.pushly.feature.stats

import java.time.Instant
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlinx.serialization.Serializable

/** `get_battle_stats()` (shared/contracts/battle-stats.schema.json, D-067): the trophy-first main section of Stats. */
@Serializable
data class BattleStats(
    val trophies: Int,
    val bestTrophies: Int,
    val league: String,
    val tier: String? = null,
    val next: Next? = null,
    val rank: Int? = null,
    val seasonEndsAt: String? = null,
    val record: Record,
    val history: List<Point> = emptyList(),
    val recent: List<Recent> = emptyList(),
    val targets: List<Target> = emptyList(),
) {
    @Serializable data class Next(val at: Int, val league: String, val tier: String? = null)

    @Serializable
    data class Record(val wins: Int, val losses: Int, val draws: Int, val winStreak: Int, val bestWinStreak: Int) {
        val played: Int get() = wins + losses + draws

        /** Win rate in percent, null before the first battle. */
        val winRate: Int? get() = if (played == 0) null else (wins * 100.0 / played).roundToInt()
    }

    @Serializable data class Point(val at: String, val trophies: Int)

    @Serializable
    data class Recent(
        val battleId: String,
        val mode: String,
        val opponent: String,
        val result: String,
        val delta: Int? = null,
        val ranked: Boolean,
        val at: String,
    )

    @Serializable
    data class Target(val userId: String, val username: String, val avatarPreset: String? = null, val trophies: Int, val gap: Int)

    /** Progress from the current tier's start to the next step (0…1); 1 at Legend. */
    val progressToNext: Double
        get() {
            val n = next ?: return 1.0
            val start = STEPS.lastOrNull { it <= trophies } ?: 0
            return ((trophies - start).toDouble() / maxOf(n.at - start, 1)).coerceIn(0.0, 1.0)
        }

    /** Days left in the season (UTC month), null without a date. */
    fun seasonDaysLeft(nowMs: Long = System.currentTimeMillis()): Int? {
        val end = seasonEndsAt?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() } ?: return null
        return maxOf(0, ceil((end - nowMs) / 86_400_000.0).toInt())
    }

    companion object {
        /** Where tiers and leagues start (app.league_for). */
        val STEPS = listOf(0, 200, 400, 600, 800, 1000, 1200, 1466, 1732, 2000, 2333, 2666, 3000, 3333, 3666, 4000, 5000)

        fun decode(json: String): BattleStats = StatsData.JSON.decodeFromString(serializer(), json)

        fun glyph(league: String): String = when (league) {
            "bronze" -> "🥉"
            "silver" -> "🥈"
            "gold" -> "🥇"
            "platinum" -> "💠"
            "diamond" -> "💎"
            "champion" -> "👑"
            else -> "🔥"
        }
    }
}
