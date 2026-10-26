package app.pushly.feature.stats

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

/** Pure chart data shaping for the dashboard (doc 10 §2). Mirrors iOS `StatsSeries` — same buckets, same steps. */
object StatsSeries {
    enum class Bucket { Day, Week, Month }

    data class Bar(val start: String, val wake: Int, val battle: Int, val training: Int) {
        val total: Int get() = wake + battle + training
    }

    data class Point(val date: String, val value: Int, val isRecord: Boolean = false)

    data class HeatCell(val date: String, val reps: Int, val week: Int, val weekday: Int) {
        val level: Int get() = heatLevel(reps)
    }

    /** Milestones crossed in the period (doc 10 §3). */
    val MILESTONES = listOf(100, 500, 1000, 2500, 5000, 10_000, 25_000, 50_000, 100_000)

    private fun date(s: String): LocalDate? = runCatching { LocalDate.parse(s) }.getOrNull()

    /** Day bars up to 31 days, week bars up to 53 weeks, month bars beyond. */
    fun bucket(from: String, to: String): Bucket {
        val a = date(from) ?: return Bucket.Day
        val b = date(to) ?: return Bucket.Day
        val days = ChronoUnit.DAYS.between(a, b) + 1
        return when {
            days <= 31 -> Bucket.Day
            days <= 371 -> Bucket.Week
            else -> Bucket.Month
        }
    }

    private fun bucketStart(d: LocalDate, bucket: Bucket): LocalDate = when (bucket) {
        Bucket.Day -> d
        Bucket.Week -> d.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        Bucket.Month -> d.withDayOfMonth(1)
    }

    private fun step(d: LocalDate, bucket: Bucket): LocalDate = when (bucket) {
        Bucket.Day -> d.plusDays(1)
        Bucket.Week -> d.plusWeeks(1)
        Bucket.Month -> d.plusMonths(1)
    }

    /** Stacked bars for the whole period, empty buckets included. */
    fun bars(stats: StatsData): List<Bar> {
        val bucket = bucket(stats.from, stats.to)
        val from = date(stats.from) ?: return emptyList()
        val to = date(stats.to) ?: return emptyList()
        val sums = mutableMapOf<String, Bar>()
        for (day in stats.daily) {
            val d = date(day.date) ?: continue
            val key = bucketStart(d, bucket).toString()
            val bar = sums[key] ?: Bar(key, 0, 0, 0)
            sums[key] = bar.copy(wake = bar.wake + day.wake, battle = bar.battle + day.battle, training = bar.training + day.training)
        }
        val out = mutableListOf<Bar>()
        var cursor = bucketStart(from, bucket)
        while (!cursor.isAfter(to)) {
            val key = cursor.toString()
            out += sums[key] ?: Bar(key, 0, 0, 0)
            cursor = step(cursor, bucket)
        }
        return out
    }

    /** Running total of all reps (starts at everything before the period). */
    fun cumulative(stats: StatsData): List<Point> {
        var total = stats.cumulativeBefore
        val out = mutableListOf(Point(stats.from, total))
        for (day in stats.daily) {
            total += day.total
            if (day.date == stats.from) out[0] = Point(stats.from, total) else out += Point(day.date, total)
        }
        if (out.last().date != stats.to) out += Point(stats.to, total)
        return out
    }

    fun milestonesReached(stats: StatsData): List<Point> {
        var total = stats.cumulativeBefore
        val out = mutableListOf<Point>()
        for (day in stats.daily) {
            val before = total
            total += day.total
            MILESTONES.filter { before < it && total >= it }.forEach { out += Point(day.date, it) }
        }
        return out
    }

    /** Best set per active day; `isRecord` where it beat every earlier day of the period. */
    fun bestSets(stats: StatsData): List<Point> {
        var best = 0
        return stats.daily.filter { it.bestSet > 0 }.map { day ->
            Point(day.date, day.bestSet, isRecord = day.bestSet > best).also { best = maxOf(best, day.bestSet) }
        }
    }

    /** Heatmap intensity 0…4 (doc 14 §1: 5-step sequential lime). */
    fun heatLevel(reps: Int): Int = when {
        reps < 1 -> 0
        reps < 20 -> 1
        reps < 50 -> 2
        reps < 100 -> 3
        else -> 4
    }

    /** The last 53 weeks ending with the week of [today], Monday rows. */
    fun heatmap(stats: StatsData, today: String): List<HeatCell> {
        val end = date(today) ?: return emptyList()
        val first = bucketStart(end, Bucket.Week).minusWeeks(52)
        val reps = stats.heatmap.groupBy { it.date }.mapValues { (_, v) -> v.sumOf { it.reps } }
        val out = mutableListOf<HeatCell>()
        var d = first
        var index = 0
        while (!d.isAfter(end)) {
            val key = d.toString()
            out += HeatCell(key, reps[key] ?: 0, week = index / 7, weekday = index % 7)
            index++
            d = d.plusDays(1)
        }
        return out
    }

    /** Change vs. the previous period: null when there's nothing to compare. */
    fun delta(now: Int?, before: Int?): Int? =
        if (now == null || before == null || (before <= 0 && now <= 0)) null else now - before

    /** Daily totals for the last [count] local days up to `stats.to` (missing days = 0), oldest first — the Profile
     *  mini chart (D-077). Same as iOS `StatsSeries.lastDays`. */
    fun lastDays(stats: StatsData, count: Int = 7): List<Pair<String, Int>> {
        val to = date(stats.to) ?: return emptyList()
        val totals = stats.daily.groupBy { it.date }.mapValues { (_, d) -> d.sumOf { it.total } }
        return (count - 1 downTo 0).map { back ->
            val key = to.minusDays(back.toLong()).toString()
            key to (totals[key] ?: 0)
        }
    }
}
