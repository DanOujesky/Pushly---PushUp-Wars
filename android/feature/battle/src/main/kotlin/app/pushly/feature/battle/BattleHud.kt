package app.pushly.feature.battle

import kotlinx.serialization.Serializable

/**
 * Live HUD clocks (doc 07 §2, §6; migration 0020). Same as `tools/reference/pushly_ref/battle_hud.py` and iOS
 * `BattleHud`; both pass `shared/test-vectors/battles/hud.json`. Times are ms since the battle start (server time).
 */
object BattleHud {
    const val ROUND_MS = 135_000L
    const val SET_MS = 90_000L
    const val REST_MS = ROUND_MS - SET_MS
    const val BO3_END_MS = 3 * ROUND_MS - REST_MS
    const val TURN_MS = 5_000L

    /** A Best-of-3 set ends after a pause longer than this (same gap as the result rules). */
    const val SET_GAP_MS = 2_000L

    /** [phase]: countdown | set | rest | over. */
    @Serializable data class Bo3Clock(val round: Int, val phase: String, val msLeft: Long)

    /** [turn]: anyone | me | them; [msLeft] negative = overdue, null when nobody has started. */
    @Serializable data class TurnState(val turn: String, val msLeft: Long?)

    fun bo3Clock(t: Long): Bo3Clock {
        if (t < 0) return Bo3Clock(0, "countdown", -t)
        if (t >= BO3_END_MS) return Bo3Clock(2, "over", 0)
        val round = (t / ROUND_MS).toInt()
        val within = t % ROUND_MS
        return if (within < SET_MS) Bo3Clock(round, "set", SET_MS - within) else Bo3Clock(round, "rest", ROUND_MS - within)
    }

    /** I have certainly won rounds 1 and 2: my set beat the opponent's raw count (an upper bound of their set). */
    fun bo3Clinched(mySets: List<Int>, theirRaw: List<Int>): Boolean =
        mySets.size >= 2 && theirRaw.size >= 2 && (0..1).all { mySets[it] > theirRaw[it] }

    fun turnState(t: Long, myLast: Long?, theirLast: Long?): TurnState = when {
        myLast == null && theirLast == null -> TurnState("anyone", null)
        myLast != null && (theirLast == null || myLast > theirLast) -> TurnState("them", TURN_MS - (t - myLast))
        else -> TurnState("me", TURN_MS - (t - (theirLast ?: t)))
    }

    /** My set in each Best-of-3 round so far (continuous reps, same rule as the result). */
    fun mySets(reps: List<BattleRules.Rep>): List<Int> = (0..2).map { round ->
        val inRound = reps.filter { it.round == round }
        val first = inRound.minOfOrNull { it.t } ?: return@map 0
        BattleRules.continuous(inRound, SET_GAP_MS, first + SET_MS).size
    }
}
