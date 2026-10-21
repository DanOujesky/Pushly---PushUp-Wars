package app.pushly.core.common

import kotlinx.serialization.Serializable

/**
 * When an ad may be shown (doc 13 §1, CLAUDE.md §4.5). Every ad call goes through [canShow]; the first failing rule is
 * the reason. Same rules as iOS `AdsGate` and `tools/reference/pushly_ref/ads.py` (vectors
 * `shared/test-vectors/ads/gate.json`). "Day" caps are rolling 24 h windows.
 */
object AdsGate {
    enum class Kind { Interstitial, Banner, Rewarded }

    val placements: Map<String, Kind> = mapOf(
        "battle_results_interstitial" to Kind.Interstitial,
        "ranks_banner" to Kind.Banner,
        "stats_banner" to Kind.Banner,
        "clan_banner" to Kind.Banner,
        "rewarded_streak_freeze" to Kind.Rewarded,
        "rewarded_extra_ghost" to Kind.Rewarded,
    )

    @Serializable data class Shown(val placement: String, val atMs: Long)

    @Serializable data class Context(
        val isPro: Boolean = false,
        val wakeActive: Boolean = false,
        val lastWakeEndedMs: Long? = null,
        val cameraActive: Boolean = false,
        /** none | matchmaking | lobby | live | results */
        val battlePhase: String = "none",
        /** other | onboarding | alarm_editor | alarm_health | wake | camera | battle */
        val screen: String = "other",
        val completedSessions: Int = 0,
        val nowMs: Long = 0,
        val lastTapMs: Long? = null,
        val shown: List<Shown> = emptyList(),
        val battlesSinceInterstitial: Int = 0,
        val freezesAvailable: Int = 0,
    )

    data class Verdict(val allowed: Boolean, val reason: String)

    private const val DAY = 24L * 3600 * 1000
    private val forbiddenScreens = setOf("onboarding", "alarm_editor", "alarm_health", "wake", "camera", "battle")
    private val busyBattle = setOf("matchmaking", "lobby", "live", "results")

    private fun count(shown: List<Shown>, now: Long, window: Long, which: Set<String>) =
        shown.count { it.placement in which && now - it.atMs < window }

    fun canShow(placement: String, ctx: Context): Verdict {
        val kind = placements[placement] ?: return Verdict(false, "unknown_placement")
        val now = ctx.nowMs
        val no = { reason: String -> Verdict(false, reason) }
        if (ctx.isPro) return no("pro")
        if (ctx.wakeActive) return no("wake_active")
        ctx.lastWakeEndedMs?.let { if (now - it < 10 * 60 * 1000L) return no("wake_cooldown") }
        if (ctx.cameraActive) return no("camera_active")
        if (ctx.battlePhase in busyBattle) return no("battle_active")
        if (ctx.screen in forbiddenScreens) return no("forbidden_screen")
        if (ctx.completedSessions < 2) return no("new_user")
        if (kind != Kind.Banner) {
            val nonBanner = placements.filterValues { it != Kind.Banner }.keys
            if (count(ctx.shown, now, DAY, nonBanner) >= 8) return no("global_cap")
        }
        if (kind == Kind.Interstitial) ctx.lastTapMs?.let { if (now - it < 2000) return no("tap_guard") }
        when (placement) {
            "battle_results_interstitial" -> {
                if (ctx.battlesSinceInterstitial < 3) return no("battle_frequency")
                ctx.shown.filter { it.placement == placement }.maxOfOrNull { it.atMs }?.let {
                    if (now - it < 4 * 60 * 1000L) return no("min_gap")
                }
                if (count(ctx.shown, now, DAY, setOf(placement)) >= 6) return no("daily_cap")
            }
            "rewarded_streak_freeze" -> {
                if (ctx.freezesAvailable > 0) return no("has_freeze")
                if (count(ctx.shown, now, 7 * DAY, setOf(placement)) >= 1) return no("weekly_cap")
            }
            "rewarded_extra_ghost" -> if (count(ctx.shown, now, DAY, setOf(placement)) >= 3) return no("daily_cap")
        }
        return Verdict(true, "ok")
    }
}
