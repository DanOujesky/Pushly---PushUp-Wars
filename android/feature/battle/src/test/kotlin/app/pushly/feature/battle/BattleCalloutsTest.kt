package app.pushly.feature.battle

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Battle announcer rules (D-066) — same cases as iOS BattleCalloutsTests. */
class BattleCalloutsTest {
    @Test
    fun countdownOncePerSecondThenGo() {
        val a = BattleAnnouncer()
        assertEquals(listOf(BattleCallout.Countdown(3)), a.countdown(3))
        assertTrue(a.countdown(3).isEmpty())
        assertEquals(listOf(BattleCallout.Countdown(2)), a.countdown(2))
        assertEquals(listOf(BattleCallout.Go), a.live(0, 0, 0, 60, 0))
    }

    @Test
    fun leadChangesAndOpponentReps() {
        val a = BattleAnnouncer()
        a.live(0, 0, 0, 60, 0)
        assertEquals(listOf(BattleCallout.TookLead), a.live(1, 0, 0, 59, 3000))
        assertEquals(listOf(BattleCallout.OpponentRep, BattleCallout.Tied), a.live(1, 1, 1, 58, 6000))
        assertEquals(listOf(BattleCallout.OpponentRep), a.live(1, 2, 2, 58, 7000))
    }

    @Test
    fun behindMilestonesOnceUntilLevel() {
        val a = BattleAnnouncer()
        a.live(0, 0, 0, 60, 0)
        a.live(0, 1, 1, 59, 3000)
        assertEquals(listOf(BattleCallout.OpponentRep, BattleCallout.Behind(3)), a.live(0, 3, 3, 55, 6000))
        assertEquals(listOf(BattleCallout.OpponentRep), a.live(1, 4, 4, 54, 9000))
        assertEquals(listOf(BattleCallout.OpponentRep, BattleCallout.Behind(5)), a.live(1, 6, 6, 50, 12000))
    }

    @Test
    fun clockMarksOnce() {
        val a = BattleAnnouncer()
        a.live(null, null, 0, 31, 0)
        assertEquals(listOf(BattleCallout.SecondsLeft(30)), a.live(null, null, 0, 30, 1000))
        assertTrue(a.live(null, null, 0, 30, 1200).isEmpty())
        assertEquals(listOf(BattleCallout.SecondsLeft(10)), a.live(null, null, 0, 10, 21000))
    }
}
