import Foundation

/// `get_battle_stats()` (shared/contracts/battle-stats.schema.json, D-067): the trophy-first main section of Stats.
public struct BattleStats: Codable, Hashable, Sendable {
    public struct Next: Codable, Hashable, Sendable {
        public var at: Int
        public var league: String
        public var tier: String?
    }

    public struct Record: Codable, Hashable, Sendable {
        public var wins: Int
        public var losses: Int
        public var draws: Int
        public var winStreak: Int
        public var bestWinStreak: Int

        public var played: Int { wins + losses + draws }
        /// Win rate in percent, nil before the first battle.
        public var winRate: Int? { played == 0 ? nil : Int((Double(wins) * 100 / Double(played)).rounded()) }
    }

    public struct Point: Codable, Hashable, Sendable {
        public var at: String
        public var trophies: Int
    }

    public struct Recent: Codable, Hashable, Sendable, Identifiable {
        public var battleId: String
        public var mode: String
        public var opponent: String
        public var result: String
        public var delta: Int?
        public var ranked: Bool
        public var at: String
        public var id: String { battleId }
    }

    public struct Target: Codable, Hashable, Sendable, Identifiable {
        public var userId: String
        public var username: String
        public var avatarPreset: String?
        public var trophies: Int
        public var gap: Int
        public var id: String { userId }
    }

    public var trophies: Int
    public var bestTrophies: Int
    public var league: String
    public var tier: String?
    public var next: Next?
    public var rank: Int?
    public var seasonEndsAt: String?
    public var record: Record
    public var history: [Point]
    public var recent: [Recent]
    public var targets: [Target]

    /// Progress from the current tier's start to the next step (0…1); 1 at Legend.
    public var progressToNext: Double {
        guard let next else { return 1 }
        let start = Self.steps.last { $0 <= trophies } ?? 0
        let span = Double(max(next.at - start, 1))
        return min(max(Double(trophies - start) / span, 0), 1)
    }

    /// Where tiers and leagues start (app.league_for).
    static let steps = [0, 200, 400, 600, 800, 1000, 1200, 1466, 1732, 2000, 2333, 2666, 3000, 3333, 3666, 4000, 5000]

    /// Days left in the season (UTC month), nil without a date.
    public func seasonDaysLeft(now: Date = Date()) -> Int? {
        guard let s = seasonEndsAt, let end = ISO8601DateFormatter().date(from: s) else { return nil }
        return max(0, Int(ceil(end.timeIntervalSince(now) / 86400)))
    }

    public static func leagueName(_ league: String, _ tier: String?) -> String {
        let name = switch league {
        case "bronze": String(localized: "Bronze")
        case "silver": String(localized: "Silver")
        case "gold": String(localized: "Gold")
        case "platinum": String(localized: "Platinum")
        case "diamond": String(localized: "Diamond")
        case "champion": String(localized: "Champion")
        default: String(localized: "Legend")
        }
        return tier.map { "\(name) \($0)" } ?? name
    }

    public static func glyph(_ league: String) -> String {
        switch league {
        case "bronze": "🥉"
        case "silver": "🥈"
        case "gold": "🥇"
        case "platinum": "💠"
        case "diamond": "💎"
        case "champion": "👑"
        default: "🔥"
        }
    }
}
