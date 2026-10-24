package app.pushly.feature.battle

/** What the battle announcer says / plays (doc 07 §6 "more action", D-066). Same rules as iOS `BattleAnnouncer`. */
sealed interface BattleCallout {
    data class Countdown(val seconds: Int) : BattleCallout
    data object Go : BattleCallout

    /** The opponent did a rep (sound only). */
    data object OpponentRep : BattleCallout
    data object TookLead : BattleCallout
    data object LostLead : BattleCallout
    data object Tied : BattleCallout

    /** Fell this many reps behind (3, 5, 10 — each once until you're level again). */
    data class Behind(val reps: Int) : BattleCallout
    data class SecondsLeft(val seconds: Int) : BattleCallout
}

class BattleAnnouncer {
    private var lastCountdown: Int? = null
    private var wentLive = false
    private var lastTheirs = 0
    private var lastSign = 0
    private val announcedBehind = HashSet<Int>()
    private val announcedTimes = HashSet<Int>()
    private var lastVoiceAt = Long.MIN_VALUE / 2

    /** Before GO: one call per second of the countdown. */
    fun countdown(seconds: Int): List<BattleCallout> {
        if (seconds == lastCountdown || seconds !in 1..3) return emptyList()
        lastCountdown = seconds
        return listOf(BattleCallout.Countdown(seconds))
    }

    /**
     * While live. [mine] / [theirs] = the scores that decide the battle right now (null = no lead in this mode, e.g.
     * Turns), [secondsLeft] = the mode clock, [nowMs] = monotonic ms.
     */
    fun live(mine: Int?, theirs: Int?, theirTotal: Int, secondsLeft: Int?, nowMs: Long): List<BattleCallout> {
        val out = ArrayList<BattleCallout>()
        if (!wentLive) {
            wentLive = true
            out += BattleCallout.Go
            lastVoiceAt = nowMs
        }
        if (theirTotal > lastTheirs) out += BattleCallout.OpponentRep
        lastTheirs = theirTotal
        if (mine != null && theirs != null) {
            val diff = mine - theirs
            val sign = Integer.signum(diff)
            var voice: BattleCallout? = null
            if (sign != lastSign) {
                voice = when {
                    sign > 0 -> BattleCallout.TookLead
                    sign < 0 -> BattleCallout.LostLead
                    else -> BattleCallout.Tied
                }
                lastSign = sign
            }
            if (diff >= 0) announcedBehind.clear()
            val milestone = BEHIND_MILESTONES.lastOrNull { -diff >= it }
            if (milestone != null && milestone !in announcedBehind) {
                announcedBehind += BEHIND_MILESTONES.filter { it <= milestone }
                voice = BattleCallout.Behind(milestone)
            }
            if (voice != null && nowMs - lastVoiceAt >= MIN_VOICE_GAP_MS) {
                out += voice
                lastVoiceAt = nowMs
            }
        }
        val mark = TIME_MARKS.firstOrNull { it == secondsLeft }
        if (mark != null && mark !in announcedTimes) {
            announcedTimes += mark
            out += BattleCallout.SecondsLeft(mark)
            lastVoiceAt = nowMs
        }
        return out
    }

    companion object {
        /** Voice lines closer than this are dropped (sounds and the clock always play). */
        const val MIN_VOICE_GAP_MS = 2500L
        private val BEHIND_MILESTONES = listOf(3, 5, 10)
        private val TIME_MARKS = listOf(30, 10)
    }
}
