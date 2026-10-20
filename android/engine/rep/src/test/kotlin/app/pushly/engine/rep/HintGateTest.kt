package app.pushly.engine.rep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Same cases as iOS HintGateTests. */
class HintGateTest {
    @Test
    fun rateLimitedAndTipAfterThreeInARow() {
        val gate = HintGate()
        assertEquals(false, gate.offer(RejectReason.NotDeepEnough, 0)?.showTip)
        assertNull(gate.offer(RejectReason.NotDeepEnough, 1000))
        assertEquals(false, gate.offer(RejectReason.NotDeepEnough, 2000)?.showTip)
        assertEquals(false, gate.offer(RejectReason.NotDeepEnough, 4000)?.showTip)
        assertEquals(true, gate.offer(RejectReason.NotDeepEnough, 6000)?.showTip)
        assertEquals(false, gate.offer(RejectReason.HipsSagging, 8000)?.showTip)
    }

    @Test
    fun guidanceBeforeThePlank() {
        assertEquals(Guidance.StepIntoFrame, Guidance.current(RepState.NotReady, null, personVisible = false, tooDark = false))
        assertEquals(Guidance.Ready, Guidance.current(RepState.Top, null, personVisible = true, tooDark = false))
        assertEquals(Guidance.TurnOnLight, Guidance.current(RepState.Top, null, personVisible = true, tooDark = true))
    }
}
