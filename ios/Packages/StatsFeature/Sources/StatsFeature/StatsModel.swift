import Core
import Foundation
import Observation

/// Loads the Stats tab (doc 10 §2) and the achievements list. Periods are cached for the life of the screen.
@MainActor
@Observable
public final class StatsModel {
    public typealias FetchStats = @Sendable (_ period: String) async throws -> Data
    public typealias FetchAchievements = @Sendable () async throws -> Data
    public typealias FetchBattle = @Sendable () async throws -> Data

    public var period: StatsData.Period = .week
    public private(set) var cache: [StatsData.Period: StatsData] = [:]
    public private(set) var achievements: [AchievementItem] = []
    /// Trophies first (D-067); push-ups are the secondary section.
    public private(set) var battle: BattleStats?
    public private(set) var loading = false
    public private(set) var failed = false

    private let fetchStats: FetchStats
    private let fetchAchievements: FetchAchievements
    private let fetchBattle: FetchBattle?

    public init(fetchStats: @escaping FetchStats, fetchAchievements: @escaping FetchAchievements,
                fetchBattle: FetchBattle? = nil) {
        self.fetchStats = fetchStats
        self.fetchAchievements = fetchAchievements
        self.fetchBattle = fetchBattle
    }

    public func loadBattle() async {
        guard let fetchBattle else { return }
        do {
            battle = try JSONDecoder().decode(BattleStats.self, from: try await fetchBattle())
        } catch {
            PLog.error("battle stats load failed: \(error)")
        }
    }

    public var stats: StatsData? { cache[period] }

    public func select(_ period: StatsData.Period) async {
        self.period = period
        if cache[period] == nil { await load() }
    }

    public func load() async {
        let wanted = period
        loading = true
        defer { loading = false }
        do {
            let data = try await fetchStats(wanted.rawValue)
            cache[wanted] = try JSONDecoder().decode(StatsData.self, from: data)
            failed = false
        } catch {
            PLog.error("stats load failed: \(error)")
            failed = cache[wanted] == nil
        }
    }

    public func refresh() async {
        cache = [:]
        await loadBattle()
        await load()
        await loadAchievements()
    }

    public func loadAchievements() async {
        do {
            achievements = try JSONDecoder().decode([AchievementItem].self, from: try await fetchAchievements())
        } catch {
            PLog.error("achievements load failed: \(error)")
        }
    }

    /// Achievements grouped in definition order.
    public var achievementGroups: [AchievementGroup] {
        var order: [String] = []
        var byGroup: [String: [AchievementItem]] = [:]
        for item in achievements {
            if byGroup[item.group] == nil { order.append(item.group) }
            byGroup[item.group, default: []].append(item)
        }
        return order.map { AchievementGroup(group: $0, items: byGroup[$0] ?? []) }
    }
}

public struct AchievementGroup: Hashable, Sendable, Identifiable {
    public var group: String
    public var items: [AchievementItem]
    public var id: String { group }
}
