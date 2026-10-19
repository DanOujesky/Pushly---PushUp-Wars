package app.pushly.engine.rep

import app.pushly.engine.rep.generated.PushupSpecV1
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same checks as iOS SpecTests. */
class SpecTest {
    @Test
    fun specVersionIsOne() {
        assertEquals(1, RepEngineInfo.SPEC_VERSION)
    }

    @Test
    fun thresholdsAreOrdered() {
        assertTrue(PushupSpecV1.Elbow.BOTTOM_MAX_DEG < PushupSpecV1.Elbow.TOP_MIN_DEG)
        assertTrue(PushupSpecV1.Elbow.BOTTOM_MAX_DEG in PushupSpecV1.CalibrationBounds.BOTTOM_MAX_DEG)
        assertTrue(PushupSpecV1.Tempo.MIN_REP_MS < PushupSpecV1.Tempo.MAX_REP_MS)
    }
}
