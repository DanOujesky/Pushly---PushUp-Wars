package app.pushly.core.alarm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

/** Same cases as iOS WidgetSnapshotTests. */
class WidgetSnapshotTest {
    private val zone = ZoneId.of("Europe/Prague")

    @Test
    fun upcomingIsSortedEnabledAndCapped() {
        val a = AlarmSchedule.newDefault("a").copy(label = "Gym")
        val b = AlarmSchedule.newDefault("b").copy(enabled = false)
        val now = Instant.parse("2026-10-21T10:00:00Z")
        val list = WidgetSnapshot.upcoming(listOf(a, b), now, zone)
        assertTrue(list.isNotEmpty() && list.size <= WidgetSnapshot.MAX_UPCOMING)
        assertTrue(list.all { it.at.isAfter(now) && it.label == "Gym" })
        assertEquals(list.sortedBy { it.at }, list)
    }

    @Test
    fun repsTodayExpiresAtMidnight() {
        val snap = WidgetSnapshot(emptyList(), 3, 40, "2026-10-21")
        assertEquals(40, snap.repsToday(Instant.parse("2026-10-21T10:00:00Z"), zone))
        assertNull(snap.repsToday(Instant.parse("2026-10-22T10:00:00Z"), zone))
    }
}
