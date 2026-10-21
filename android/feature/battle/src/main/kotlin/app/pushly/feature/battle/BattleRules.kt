package app.pushly.feature.battle

import kotlinx.serialization.Serializable
import kotlin.math.floor

/**
 * Battle results (doc 07 §2) — client copy of the server rules for the provisional result and live HUDs. Same as
 * `tools/reference/pushly_ref/battle.py`, SQL `app.decide_battle` and iOS `BattleRules`; all pass
 * `shared/test-vectors/battles/results.json`. The server's settled result always wins.
 */
object BattleRules {
    /** [t]: ms since the battle start (server time). */
    @Serializable data class Rep(val t: Long, val q: Int, val round: Int = 0)

    @Serializable data class Side(
        val reps: Int,
        val avgQuality: Int,
        val lastT: Long? = null,
        val finishT: Long? = null,
        val rounds: Int? = null,
    )

    @Serializable data class RoundResult(val a: Int, val b: Int, val winner: String? = null)

    @Serializable data class Result(
        val winner: String? = null,
        val reason: String,
        val a: Side,
        val b: Side,
        val rounds: List<RoundResult>? = null,
    )

    private fun avg(qs: List<Int>): Int = if (qs.isEmpty()) 0 else floor(qs.sum().toDouble() / qs.size + 0.5).toInt()

    private fun side(reps: List<Rep>) = Side(reps.size, avg(reps.map { it.q }), reps.lastOrNull()?.t)

    private fun sorted(reps: List<Rep>) = reps.withIndex().sortedWith(compareBy({ it.value.t }, { it.index })).map { it.value }

    internal fun continuous(reps: List<Rep>, gap: Long, cap: Long): List<Rep> {
        val out = mutableListOf<Rep>()
        for (r in sorted(reps)) {
            if (r.t > cap) break
            val last = out.lastOrNull()
            if (last != null && r.t - last.t > gap) break
            out += r
        }
        return out
    }

    /** Compares fields in order; `true` = higher wins. null loses. */
    private fun compare(a: Side, b: Side, vararg keys: Pair<(Side) -> Long?, Boolean>): String? {
        for ((key, higher) in keys) {
            val x = key(a)
            val y = key(b)
            if (x == y) continue
            if (x == null) return "b"
            if (y == null) return "a"
            return if ((x > y) == higher) "a" else "b"
        }
        return null
    }

    private val reps: (Side) -> Long? = { it.reps.toLong() }
    private val quality: (Side) -> Long? = { it.avgQuality.toLong() }
    private val lastT: (Side) -> Long? = { it.lastT }
    private val finishT: (Side) -> Long? = { it.finishT }
    private val roundsWon: (Side) -> Long? = { it.rounds?.toLong() }

    fun decide(mode: String, variant: Map<String, Int>, a: List<Rep>, b: List<Rep>): Result = when (mode) {
        "max_reps" -> {
            val cap = (variant["durationS"] ?: 60) * 1000L
            val sa = side(a.filter { it.t <= cap })
            val sb = side(b.filter { it.t <= cap })
            val w = compare(sa, sb, reps to true, quality to true, lastT to false)
            Result(w, if (w == null) "draw" else "reps", sa, sb)
        }
        "speed" -> {
            val target = variant["targetReps"] ?: 20
            fun speedSide(r: List<Rep>): Side {
                val within = sorted(r).filter { it.t <= 120_000 }
                return side(within.take(target)).copy(finishT = if (within.size >= target) within[target - 1].t else null)
            }
            val sa = speedSide(a)
            val sb = speedSide(b)
            if (sa.finishT != null || sb.finishT != null) {
                val w = compare(sa, sb, finishT to false)
                Result(w, if (w == null) "draw" else "target", sa, sb)
            } else {
                val w = compare(sa, sb, reps to true, lastT to false)
                Result(w, if (w == null) "draw" else "reps", sa, sb)
            }
        }
        "endurance" -> {
            val sa = side(continuous(a, 3000, 600_000))
            val sb = side(continuous(b, 3000, 600_000))
            val w = compare(sa, sb, reps to true, lastT to false)
            Result(w, if (w == null) "draw" else "reps", sa, sb)
        }
        "best_of_3" -> {
            var winsA = 0
            var winsB = 0
            val totalA = mutableListOf<Rep>()
            val totalB = mutableListOf<Rep>()
            val rounds = mutableListOf<RoundResult>()
            for (rnd in 0 until 3) {
                fun set(r: List<Rep>): List<Rep> {
                    val rr = r.filter { it.round == rnd }
                    val first = rr.minOfOrNull { it.t } ?: 0L
                    return continuous(rr, 2000, first + 90_000)
                }
                val setA = set(a)
                val setB = set(b)
                totalA += setA
                totalB += setB
                val rw = when {
                    setA.size > setB.size -> "a"
                    setB.size > setA.size -> "b"
                    else -> null
                }
                if (rw == "a") winsA++ else if (rw == "b") winsB++
                rounds += RoundResult(setA.size, setB.size, rw)
                if (maxOf(winsA, winsB) >= 2) break
            }
            val sa = side(totalA).copy(rounds = winsA)
            val sb = side(totalB).copy(rounds = winsB)
            var w = compare(sa, sb, roundsWon to true)
            var reason = "rounds"
            if (w == null) {
                w = compare(sa, sb, reps to true, quality to true)
                reason = if (w == null) "draw" else "reps"
            }
            Result(w, reason, sa, sb, rounds)
        }
        "turns" -> {
            val window = 5000L + minOf(variant["latencyMs"] ?: 0, 500)
            data class E(val r: Rep, val p: String, val i: Int)
            val events = (a.mapIndexed { i, r -> E(r, "a", i) } + b.mapIndexed { i, r -> E(r, "b", i) })
                .sortedWith(compareBy({ it.r.t }, { it.p }, { it.i }))
            val countedA = mutableListOf<Rep>()
            val countedB = mutableListOf<Rep>()
            var prev: E? = null
            var loser: String? = null
            var stopped = false
            for (e in events) {
                val p = prev
                if (p != null && p.p == e.p) continue
                if (p != null && e.r.t - p.r.t > window) {
                    loser = e.p
                    stopped = true
                    break
                }
                if (e.p == "a") countedA += e.r else countedB += e.r
                prev = e
                if (countedA.size + countedB.size >= 200) {
                    stopped = true
                    break
                }
            }
            val last = prev
            if (!stopped && last != null) loser = if (last.p == "a") "b" else "a"
            val sa = side(countedA)
            val sb = side(countedB)
            val l = loser
            if (l != null) {
                Result(if (l == "a") "b" else "a", "turn_missed", sa, sb)
            } else {
                val w = if (last == null) null else compare(sa, sb, quality to true)
                Result(w, if (w == null) "draw" else "quality", sa, sb)
            }
        }
        else -> Result(null, "draw", side(emptyList()), side(emptyList()))
    }
}
