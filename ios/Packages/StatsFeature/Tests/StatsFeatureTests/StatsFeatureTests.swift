import Foundation
import Testing
@testable import StatsFeature

enum RepoFile {
    static func url(_ relative: String, file: StaticString = #filePath) -> URL {
        // .../ios/Packages/StatsFeature/Tests/StatsFeatureTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent(relative)
    }
}

private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: RepoFile.url("shared/contracts/fixtures/\(name)")))
}

private func day(_ date: String, wake: Int = 0, training: Int = 0, best: Int = 0) -> StatsData.Day {
    .init(date: date, wake: wake, battle: 0, training: training, total: wake + training, bestSet: best, avgQuality: nil)
}

private func stats(from: String, to: String, before: Int = 0, daily: [StatsData.Day]) throws -> StatsData {
    var s = try fixture("stats.json", as: StatsData.self)
    s.from = from
    s.to = to
    s.cumulativeBefore = before
    s.daily = daily
    return s
}

struct StatsContractTests {
    @Test func decodesStatsFixture() throws {
        let s = try fixture("stats.json", as: StatsData.self)
        #expect(s.period == .week)
        #expect(s.records.bestSet == 60)
        #expect(s.progress.level == 6)
        #expect(s.wakes.first?.completedMinute == 422)
    }

    @Test func decodesAchievementsFixture() throws {
        let items = try fixture("achievements.json", as: [AchievementItem].self)
        #expect(items.count == 3)
        #expect(items[0].unlocked)
        #expect(!items[1].unlocked)
    }
}

struct StatsSeriesTests {
    @Test func bucketsByLength() {
        #expect(StatsSeries.bucket(from: "2026-10-15", to: "2026-10-21") == .day)
        #expect(StatsSeries.bucket(from: "2026-09-22", to: "2026-10-21") == .day)
        #expect(StatsSeries.bucket(from: "2025-10-22", to: "2026-10-21") == .week)
        #expect(StatsSeries.bucket(from: "2024-01-01", to: "2026-10-21") == .month)
    }

    @Test func dayBarsFillGaps() throws {
        let s = try stats(from: "2026-10-15", to: "2026-10-21", daily: [day("2026-10-16", wake: 20), day("2026-10-20", training: 5)])
        let bars = StatsSeries.bars(s)
        #expect(bars.count == 7)
        #expect(bars[1].wake == 20)
        #expect(bars[5].training == 5)
        #expect(bars.map(\.total).reduce(0, +) == 25)
    }

    @Test func weekBarsStartOnMonday() throws {
        // 2026-10-21 is a Wednesday; its week starts Monday 2026-10-19.
        let s = try stats(from: "2025-10-22", to: "2026-10-21",
                          daily: [day("2026-10-20", wake: 10), day("2026-10-21", training: 4), day("2026-10-18", wake: 1)])
        let bars = StatsSeries.bars(s)
        #expect(bars.last?.start == "2026-10-19")
        #expect(bars.last?.total == 14)
        #expect(bars[bars.count - 2].start == "2026-10-12")
        #expect(bars[bars.count - 2].total == 1)
    }

    @Test func cumulativeStartsWithEarlierReps() throws {
        let s = try stats(from: "2026-10-15", to: "2026-10-21", before: 95,
                          daily: [day("2026-10-16", wake: 10), day("2026-10-20", training: 400)])
        let points = StatsSeries.cumulative(s)
        #expect(points.map(\.value) == [95, 105, 505, 505])
        #expect(points.map(\.date) == ["2026-10-15", "2026-10-16", "2026-10-20", "2026-10-21"])
        #expect(StatsSeries.milestonesReached(s).map(\.value) == [100, 500])
    }

    @Test func bestSetRecords() throws {
        let s = try stats(from: "2026-10-15", to: "2026-10-21",
                          daily: [day("2026-10-15", best: 20), day("2026-10-16", best: 15), day("2026-10-17"),
                                  day("2026-10-18", best: 25)])
        let points = StatsSeries.bestSets(s)
        #expect(points.map(\.value) == [20, 15, 25])
        #expect(points.map(\.isRecord) == [true, false, true])
    }

    @Test func heatLevels() {
        #expect([0, 1, 19, 20, 49, 50, 99, 100, 500].map(StatsSeries.heatLevel) == [0, 1, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test func heatmapIs53WeeksOfMondayRows() throws {
        var s = try stats(from: "2026-10-15", to: "2026-10-21", daily: [])
        s.heatmap = [.init(date: "2026-10-19", reps: 30)]
        let cells = StatsSeries.heatmap(s, today: "2026-10-21")
        #expect(cells.count == 52 * 7 + 3)                   // full weeks + Mon–Wed of this week
        #expect(cells.first?.weekday == 0)
        #expect(cells.last?.week == 52)
        #expect(cells.first { $0.date == "2026-10-19" }?.level == 2)
    }

    @Test func deltas() {
        #expect(StatsSeries.delta(10, 4) == 6)
        #expect(StatsSeries.delta(0, 0) == nil)
        #expect(StatsSeries.delta(nil, 3) == nil)
    }
}

@MainActor
struct StatsModelTests {
    @Test func loadsAndCachesPeriods() async throws {
        let data = try Data(contentsOf: RepoFile.url("shared/contracts/fixtures/stats.json"))
        let ach = try Data(contentsOf: RepoFile.url("shared/contracts/fixtures/achievements.json"))
        let model = StatsModel(fetchStats: { _ in data }, fetchAchievements: { ach })
        await model.load()
        #expect(model.stats?.kpis.reps == 110)
        await model.select(.month)
        #expect(model.cache.count == 2)
        await model.loadAchievements()
        #expect(model.achievementGroups.map(\.group) == ["wake"])
        #expect(model.achievementGroups.first?.items.count == 3)
    }

    @Test func failureShowsBanner() async {
        struct Boom: Error {}
        let model = StatsModel(fetchStats: { _ in throw Boom() }, fetchAchievements: { throw Boom() })
        await model.load()
        #expect(model.failed)
        #expect(model.stats == nil)
    }
}
