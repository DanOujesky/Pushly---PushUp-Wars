import Foundation

/// `get_stats(period)` (shared/contracts/stats.schema.json). Personal stats use the user's local days.
public struct StatsData: Codable, Hashable, Sendable {
    public enum Period: String, Codable, CaseIterable, Sendable, Identifiable {
        case week, month, year, all
        public var id: String { rawValue }
    }

    public struct Kpis: Codable, Hashable, Sendable {
        public var reps: Int
        public var repsPrev: Int
        public var bestSet: Int
        public var bestSetPrev: Int
        public var wakeSuccessPct: Int?
        public var wakeSuccessPctPrev: Int?
        public var avgQuality: Int?
        public var avgQualityPrev: Int?
    }

    public struct Day: Codable, Hashable, Sendable {
        public var date: String
        public var wake: Int
        public var battle: Int
        public var training: Int
        public var total: Int
        public var bestSet: Int
        public var avgQuality: Int?
    }

    public struct Wake: Codable, Hashable, Sendable {
        public var date: String
        public var status: String
        public var scheduledAt: String?
        public var completedAt: String?
        public var scheduledMinute: Double?
        public var completedMinute: Double?
    }

    public struct HeatDay: Codable, Hashable, Sendable {
        public var date: String
        public var reps: Int
    }

    public struct Records: Codable, Hashable, Sendable {
        public var bestSet: Int
        public var maxDay: Int
        public var bestStreak: Int
        public var repsAllTime: Int
    }

    public struct Level: Codable, Hashable, Sendable {
        public var level: Int
        public var xpIntoLevel: Int
        public var xpForNext: Int
        public var xp: Int

        public var fraction: Double { xpForNext > 0 ? Double(xpIntoLevel) / Double(xpForNext) : 1 }
    }

    public struct AchievementCount: Codable, Hashable, Sendable {
        public var unlocked: Int
        public var total: Int
    }

    public var period: Period
    public var from: String
    public var to: String
    public var kpis: Kpis
    public var daily: [Day]
    public var cumulativeBefore: Int
    public var wakes: [Wake]
    public var heatmap: [HeatDay]
    public var records: Records
    public var progress: Level
    public var achievements: AchievementCount
}

/// One row of `get_achievements()` (shared/contracts/achievements.schema.json).
public struct AchievementItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var group: String
    public var title: String
    public var description: String
    /// SF Symbol name.
    public var icon: String
    public var tier: Int
    public var xp: Int
    public var unlockedAt: String?

    public var unlocked: Bool { unlockedAt != nil }
}
