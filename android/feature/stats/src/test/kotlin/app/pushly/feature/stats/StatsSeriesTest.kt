package app.pushly.feature.stats

import app.pushly.core.common.StatsService
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same cases as iOS StatsFeatureTests. */
class StatsSeriesTest {
    private fun fixture(name: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, "shared/contracts/fixtures/$name").takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("fixture not found: $name")
    }

    private fun day(date: String, wake: Int = 0, training: Int = 0, best: Int = 0) =
        StatsData.Day(date, wake, 0, training, wake + training, best)

    private fun stats(from: String, to: String, before: Int = 0, daily: List<StatsData.Day>) =
        StatsData.decode(fixture("stats.json")).copy(from = from, to = to, cumulativeBefore = before, daily = daily)

    @Test
    fun decodesFixtures() {
        val s = StatsData.decode(fixture("stats.json"))
        assertEquals("week", s.period)
        assertEquals(60, s.records.bestSet)
        assertEquals(6, s.progress.level)
        assertEquals(422.0, s.wakes.first().completedMinute ?: 0.0, 0.0)
        val items = AchievementItem.decodeList(fixture("achievements.json"))
        assertEquals(3, items.size)
        assertTrue(items[0].unlocked)
        assertFalse(items[1].unlocked)
    }

    @Test
    fun lastSevenDaysFillGaps() {
        val s = stats("2026-10-15", "2026-10-21", daily = listOf(day("2026-10-16", wake = 20), day("2026-10-21", training = 15)))
        val days = StatsSeries.lastDays(s)
        assertEquals(7, days.size)
        assertEquals("2026-10-15" to 0, days.first())
        assertEquals("2026-10-16" to 20, days[1])
        assertEquals("2026-10-21" to 15, days.last())
    }

    @Test
    fun bucketsByLength() {
        assertEquals(StatsSeries.Bucket.Day, StatsSeries.bucket("2026-10-15", "2026-10-21"))
        assertEquals(StatsSeries.Bucket.Day, StatsSeries.bucket("2026-09-22", "2026-10-21"))
        assertEquals(StatsSeries.Bucket.Week, StatsSeries.bucket("2025-10-22", "2026-10-21"))
        assertEquals(StatsSeries.Bucket.Month, StatsSeries.bucket("2024-01-01", "2026-10-21"))
    }

    @Test
    fun dayBarsFillGaps() {
        val bars = StatsSeries.bars(stats("2026-10-15", "2026-10-21", daily = listOf(day("2026-10-16", wake = 20), day("2026-10-20", training = 5))))
        assertEquals(7, bars.size)
        assertEquals(20, bars[1].wake)
        assertEquals(5, bars[5].training)
        assertEquals(25, bars.sumOf { it.total })
    }

    @Test
    fun weekBarsStartOnMonday() {
        val bars = StatsSeries.bars(
            stats("2025-10-22", "2026-10-21", daily = listOf(day("2026-10-20", wake = 10), day("2026-10-21", training = 4), day("2026-10-18", wake = 1))),
        )
        assertEquals("2026-10-19", bars.last().start)
        assertEquals(14, bars.last().total)
        assertEquals("2026-10-12", bars[bars.size - 2].start)
        assertEquals(1, bars[bars.size - 2].total)
    }

    @Test
    fun cumulativeStartsWithEarlierReps() {
        val s = stats("2026-10-15", "2026-10-21", before = 95, daily = listOf(day("2026-10-16", wake = 10), day("2026-10-20", training = 400)))
        val points = StatsSeries.cumulative(s)
        assertEquals(listOf(95, 105, 505, 505), points.map { it.value })
        assertEquals(listOf("2026-10-15", "2026-10-16", "2026-10-20", "2026-10-21"), points.map { it.date })
        assertEquals(listOf(100, 500), StatsSeries.milestonesReached(s).map { it.value })
    }

    @Test
    fun bestSetRecords() {
        val s = stats("2026-10-15", "2026-10-21", daily = listOf(day("2026-10-15", best = 20), day("2026-10-16", best = 15), day("2026-10-17"), day("2026-10-18", best = 25)))
        val points = StatsSeries.bestSets(s)
        assertEquals(listOf(20, 15, 25), points.map { it.value })
        assertEquals(listOf(true, false, true), points.map { it.isRecord })
    }

    @Test
    fun heatLevels() {
        assertEquals(listOf(0, 1, 1, 2, 2, 3, 3, 4, 4), listOf(0, 1, 19, 20, 49, 50, 99, 100, 500).map(StatsSeries::heatLevel))
    }

    @Test
    fun heatmapIs53WeeksOfMondayRows() {
        val s = stats("2026-10-15", "2026-10-21", daily = emptyList()).copy(heatmap = listOf(StatsData.HeatDay("2026-10-19", 30)))
        val cells = StatsSeries.heatmap(s, "2026-10-21")
        assertEquals(52 * 7 + 3, cells.size)
        assertEquals(0, cells.first().weekday)
        assertEquals(52, cells.last().week)
        assertEquals(2, cells.first { it.date == "2026-10-19" }.level)
    }

    @Test
    fun deltas() {
        assertEquals(6, StatsSeries.delta(10, 4))
        assertNull(StatsSeries.delta(0, 0))
        assertNull(StatsSeries.delta(null, 3))
    }

    @Test
    fun viewModelLoadsAndCachesPeriods() = runTest {
        val service = object : StatsService {
            var calls = 0
            override suspend fun stats(period: String): String = fixture("stats.json").also { calls++ }
            override suspend fun achievements(): String = fixture("achievements.json")
        }
        val vm = StatsViewModel(service)
        vm.load()
        assertEquals(110, vm.state.value.stats?.kpis?.reps)
        vm.select(StatsData.Period.Month)
        vm.select(StatsData.Period.Week)
        assertEquals(2, service.calls)
        vm.loadAchievements()
        assertEquals(listOf("wake"), vm.state.value.groups.map { it.group })
    }

    @Test
    fun viewModelFailure() = runTest {
        val vm = StatsViewModel(object : StatsService {
            override suspend fun stats(period: String): String = throw IllegalStateException("boom")
            override suspend fun achievements(): String = throw IllegalStateException("boom")
        })
        vm.load()
        assertTrue(vm.state.value.failed)
        assertNull(vm.state.value.stats)
    }
}
