package app.pushly.feature.alarm

import app.pushly.core.alarm.WakeSummary
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/** Wake tab rules (D-079) — same expectations as iOS WakeTabRulesTests. */
class WakeTabRulesTest {
    private fun summary(): WakeSummary {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, "shared/contracts/fixtures/wake_summary.json").takeIf { it.exists() }?.let { return WakeSummary.decode(it.readText()) }
            dir = dir.parentFile
        }
        error("fixture not found")
    }

    @Test
    fun weekCounts() {
        val s = summary()
        assertEquals("2026-10-19", WakeTabRules.weekDates(s).first())
        assertEquals(7, WakeTabRules.weekDates(s).size)
        assertEquals(1, WakeTabRules.beaten(s))
        assertEquals(2, WakeTabRules.challenges(s))
    }

    @Test
    fun greetingBuckets() {
        assertEquals("morning", WakeTabRules.greetingBucket(6))
        assertEquals("afternoon", WakeTabRules.greetingBucket(12))
        assertEquals("evening", WakeTabRules.greetingBucket(20))
        assertEquals("night", WakeTabRules.greetingBucket(2))
    }

    @Test
    fun countdownFraction() {
        assertEquals(0f, WakeTabRules.countdownFraction(86_400L * 2), 0f)
        assertEquals(0.5f, WakeTabRules.countdownFraction(43_200L), 0f)
        assertEquals(1f, WakeTabRules.countdownFraction(-5L), 0f)
    }
}
