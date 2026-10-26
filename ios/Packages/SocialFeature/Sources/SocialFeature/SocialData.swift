import DesignSystem
import Foundation

/// Another user (shared/contracts/user-card.schema.json).
public struct UserCard: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var username: String
    public var avatarPreset: String?
    public var country: String?
    public var level: Int
    public var trophies: Int
    /// nil when the profile isn't visible to me.
    public var streak: Int?
    /// Only in search results: none | friends | incoming | outgoing.
    public var relation: String?
    public var clanTag: String?
    /// Pushly Pro — PRO badge (D-073).
    public var pro: Bool?
    /// Pro profile frame (D-074).
    public var frame: String?
}

/// `list_friends()` (friends.schema.json).
public struct FriendsList: Codable, Hashable, Sendable {
    public struct Blocked: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var username: String
    }

    public var friends: [UserCard]
    public var incoming: [UserCard]
    public var outgoing: [UserCard]
    public var blocked: [Blocked]

    public static let empty = FriendsList(friends: [], incoming: [], outgoing: [], blocked: [])
}

/// One row of `get_friend_feed()` (friend-feed.schema.json).
public struct FeedItem: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var user: UserCard
    /// wake_beaten | achievement | level_up | best_set
    public var kind: String
    public var payload: [String: JSONValue]
    public var createdAt: String
    public var kudos: Int
    public var kudosByMe: Bool
}

/// `get_leaderboard(board, scope, period)` (leaderboard.schema.json).
public struct Leaderboard: Codable, Hashable, Sendable {
    public struct Row: Codable, Hashable, Sendable, Identifiable {
        /// Anonymous rows have no id or name.
        public struct User: Codable, Hashable, Sendable {
            public var id: String?
            public var username: String?
            public var avatarPreset: String?
            public var country: String?
            public var level: Int?
            public var streak: Int?
            public var anonymous: Bool?
            public var pro: Bool?
            public var frame: String?
        }

        public var rank: Int
        public var score: Int
        public var isMe: Bool
        public var user: User
        public var id: String { "\(rank)-\(user.id ?? "anon")-\(score)" }
    }

    public struct Me: Codable, Hashable, Sendable {
        public var rank: Int
        public var score: Int
        public var shadow: Bool
    }

    public var board: String
    public var scope: String
    public var period: String
    public var periodKey: String
    public var refreshedAt: String?
    public var needsCountry: Bool?
    public var rows: [Row]
    public var around: [Row]
    public var me: Me?
}

/// Minimal JSON value for free-form payloads.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .null   // nested objects / arrays aren't used by the feed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(s): try c.encode(s)
        case let .number(n): try c.encode(n)
        case let .bool(b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    public var string: String? { if case let .string(s) = self { s } else { nil } }
    public var int: Int? { if case let .number(n) = self { Int(n) } else { nil } }
}

/// Board choices (doc 08 §4). Battles and clans come with phases 7 / 8.
public enum Board: String, CaseIterable, Sendable, Identifiable {
    case wake, streak, reps
    public var id: String { rawValue }

    public var periods: [String] {
        switch self {
        case .wake: ["week", "month", "all"]
        case .streak: ["current"]
        case .reps: ["day", "week", "month", "all"]
        }
    }

    public var defaultPeriod: String { self == .streak ? "current" : "week" }
}

/// Another player's profile (user-profile.schema.json). `stats` is nil when their visibility hides it from me.
public struct UserProfile: Codable, Hashable, Sendable {
    public struct League: Codable, Hashable, Sendable {
        public var league: String
        public var tier: String?
    }

    public struct Stats: Codable, Hashable, Sendable {
        public struct Battles: Codable, Hashable, Sendable {
            public var wins: Int
            public var losses: Int
            public var draws: Int
            public var winStreak: Int
            public var bestWinStreak: Int
            /// Last 10 vs people, newest first: W / L / D.
            public var form: [String]

            public var played: Int { wins + losses + draws }
            public var winRate: Double { played == 0 ? 0 : Double(wins) / Double(played) }
        }

        public var repsTotal: Int
        public var bestSet: Int
        public var bestStreak: Int
        public var achievements: Int
        public var bestTrophies: Int
        public var memberSince: String
        // D-080 (migration 0036) — optional so older servers still decode
        public var achievementsTotal: Int?
        public var level: Int?
        public var xp: Int?
        public var rank: Int?
        public var wakeStreak: Int?
        public var repsWeek: Int?
        /// Push-ups per local day, oldest first, today last.
        public var last7: [Int]?
        public var battles: Battles?
    }

    /// The player's clan (D-080).
    public struct Clan: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var tag: String
        public var badge: ClanBadgeStyle?
        public var rating: Int
        public var memberCount: Int
        /// leader | co_leader | elder | member
        public var role: String
    }

    public struct HeadToHead: Codable, Hashable, Sendable {
        public var wins: Int
        public var losses: Int
        public var draws: Int
    }

    public var user: UserCard
    /// self | friends | outgoing | incoming | none
    public var relation: String
    public var visible: Bool
    public var league: League
    public var stats: Stats?
    public var headToHead: HeadToHead?
    public var clan: Clan?
}
