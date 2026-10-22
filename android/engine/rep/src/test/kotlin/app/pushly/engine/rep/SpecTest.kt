package app.pushly.engine.rep

import app.pushly.engine.rep.generated.PushupSpecV2
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same checks as iOS SpecTests. */
class SpecTest {
    @Test
    fun specVersionIsTwo() {
        assertEquals(2, RepEngineInfo.SPEC_VERSION)
    }

    @Test
    fun thresholdsAreOrdered() {
        assertTrue(PushupSpecV2.Elbow.BOTTOM_MAX_DEG < PushupSpecV2.Elbow.TOP_MIN_DEG)
        assertTrue(PushupSpecV2.Elbow.BOTTOM_MAX_DEG in PushupSpecV2.CalibrationBounds.BOTTOM_MAX_DEG)
        assertTrue(PushupSpecV2.Tempo.MIN_REP_MS < PushupSpecV2.Tempo.MAX_REP_MS)
    }
}
