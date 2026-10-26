package app.pushly.feature.battle

import kotlin.math.abs

/**
 * How a finished battle went, for History (D-077): the final score from my side, by how much it was won or lost and
 * whether it was a close call. Same rules as iOS `BattleRecap`; both pass shared/test-vectors/battles/recap.json.
 */
data class BattleRecap(val outcome: Outcome, val mine: Int, val theirs: Int, val margin: Margin) {
    enum class Outcome { Win, Loss, Draw }

    sealed interface Margin {
        /** Difference in push-ups. */
        data class Reps(val n: Int) : Margin
        /** Speed: difference in finish time, ms. */
        data class Time(val ms: Long) : Margin
        /** Best of 3: rounds won by me and by them. */
        data class Rounds(val mine: Int, val theirs: Int) : Margin
        /** Same reps; better average form won. */
        data object Form : Margin
        data class Forfeit(val byMe: Boolean) : Margin
        data class TurnMissed(val byMe: Boolean) : Margin
        data object Draw : Margin
        data object Void : Margin
    }

    /** A nail-biter: one push-up, under a second, 2–1 in rounds, on form, or a draw. */
    val isClose: Boolean
        get() = when (val m = margin) {
            is Margin.Reps -> m.n <= 1
            is Margin.Time -> m.ms <= 1000
            is Margin.Rounds -> abs(m.mine - m.theirs) == 1
            Margin.Form, Margin.Draw -> true
            else -> false
        }

    companion object {
        fun of(battle: Battle): BattleRecap {
            val meA = battle.me == "a"
            val outcome = when (battle.winner) {
                "me" -> Outcome.Win
                "opponent" -> Outcome.Loss
                else -> Outcome.Draw
            }
            val r = battle.result
                ?: return BattleRecap(outcome, battle.myScore, battle.theirScore, if (battle.status == "void") Margin.Void else Margin.Draw)
            val me = if (meA) r.a else r.b
            val them = if (meA) r.b else r.a
            val lost = outcome == Outcome.Loss
            val myFinish = me.finishT
            val theirFinish = them.finishT
            val margin = when {
                r.reason == "forfeit" -> Margin.Forfeit(lost)
                r.reason == "turn_missed" -> Margin.TurnMissed(lost)
                r.reason == "draw" -> Margin.Draw
                r.reason == "quality" -> Margin.Form
                r.reason == "rounds" -> Margin.Rounds(me.rounds ?: 0, them.rounds ?: 0)
                r.reason == "target" && myFinish != null && theirFinish != null -> Margin.Time(abs(myFinish - theirFinish))
                outcome == Outcome.Draw && r.reason != "target" -> Margin.Draw
                else -> Margin.Reps(abs(me.reps - them.reps))
            }
            return BattleRecap(outcome, me.reps, them.reps, margin)
        }
    }
}

/** Summary of battles (newest first) for the History header. Same as iOS `HistorySummary`. */
data class HistorySummary(
    val wins: Int,
    val losses: Int,
    val draws: Int,
    val closeLosses: Int,
    val clutchWins: Int,
    val trophyNet: Int,
    /** Last up to 10 results, newest first. */
    val form: List<BattleRecap.Outcome>,
) {
    companion object {
        fun of(battles: List<Battle>): HistorySummary {
            val played = battles.filter { it.status != "void" }
            val recaps = played.map { BattleRecap.of(it) }
            return HistorySummary(
                wins = recaps.count { it.outcome == BattleRecap.Outcome.Win },
                losses = recaps.count { it.outcome == BattleRecap.Outcome.Loss },
                draws = recaps.count { it.outcome == BattleRecap.Outcome.Draw },
                closeLosses = recaps.count { it.outcome == BattleRecap.Outcome.Loss && it.isClose },
                clutchWins = recaps.count { it.outcome == BattleRecap.Outcome.Win && it.isClose },
                trophyNet = played.filter { it.ranked }.sumOf { it.myTrophies ?: 0 },
                form = recaps.take(10).map { it.outcome },
            )
        }
    }
}
