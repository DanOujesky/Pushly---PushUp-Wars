import Foundation

/// A clan in lists (clan-summary.schema.json).
public struct ClanSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var tag: String
    public var description: String
    public var joinPolicy: String
    public var minTrophies: Int
    public var country: String?
    public var warEnabled: Bool
    public var rating: Int
    public var memberCount: Int
    public var maxMembers: Int
    /// leader | co_leader | elder | member, nil when not a member.
    public var myRole: String?
    public var requested: Bool
}

public struct MemberCard: Codable, Hashable, Sendable {
    public var id: String
    public var username: String
    public var avatarPreset: String?
    public var trophies: Int?
    public var level: Int?
}

/// `get_clan()` (clan.schema.json): summary + members, requests and the war card.
public struct ClanHome: Codable, Hashable, Sendable {
    public struct Member: Codable, Hashable, Sendable, Identifiable {
        public var user: MemberCard
        public var role: String
        public var repsToday: Int
        public var warReps: Int
        public var id: String { user.id }
    }

    public struct Request: Codable, Hashable, Sendable, Identifiable {
        public var user: MemberCard
        public var message: String?
        public var id: String { user.id }
    }

    public var summary: ClanSummary
    public var members: [Member]
    public var requests: [Request]
    public var war: ClanWar?

    enum CodingKeys: String, CodingKey { case members, requests, war }

    public init(from decoder: Decoder) throws {
        summary = try ClanSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        members = try c.decode([Member].self, forKey: .members)
        requests = try c.decode([Request].self, forKey: .requests)
        war = try c.decodeIfPresent(ClanWar.self, forKey: .war)
    }

    public func encode(to encoder: Encoder) throws {
        try summary.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(members, forKey: .members)
        try c.encode(requests, forKey: .requests)
        try c.encodeIfPresent(war, forKey: .war)
    }
}

/// War card (clan-war.schema.json).
public struct ClanWar: Codable, Hashable, Sendable {
    public struct Score: Codable, Hashable, Sendable {
        public var us: Int
        public var them: Int
    }

    public struct Today: Codable, Hashable, Sendable {
        public var raw: Int
        public var counted: Int
        public var fullCap: Int
        public var halfCap: Int
    }

    public struct Top: Codable, Hashable, Sendable {
        public var user: MemberCard
        public var reps: Int
    }

    public var id: String
    public var status: String
    public var weekStart: String
    public var endsAt: String
    public var opponent: ClanSummary?
    public var score: Score
    public var myToday: Today
    public var top: [Top]
}

/// One chat message (clan-messages.schema.json).
public struct ClanMessage: Codable, Hashable, Sendable, Identifiable {
    public struct Author: Codable, Hashable, Sendable {
        public var id: String
        public var username: String
        public var avatarPreset: String?
    }

    public var id: Int
    /// text | system | kudos
    public var kind: String
    public var body: String?
    public var user: Author?
    public var createdAt: String
}

/// Roles and what they may do (doc 09 §2) — mirrors the server checks so the UI only offers allowed actions.
public enum ClanRole: String, Sendable, CaseIterable {
    case leader, coLeader = "co_leader", elder, member

    public var rank: Int {
        switch self {
        case .leader: 4
        case .coLeader: 3
        case .elder: 2
        case .member: 1
        }
    }

    public var canEditSettings: Bool { rank >= 3 }
    public var canAcceptRequests: Bool { rank >= 2 }

    public func canKick(_ other: ClanRole) -> Bool { rank >= 2 && other.rank < rank }

    /// Roles this role may give to `other`.
    public func assignable(to other: ClanRole) -> [ClanRole] {
        switch self {
        case .leader: [.coLeader, .elder, .member].filter { $0 != other }
        case .coLeader where other.rank <= 2: [.elder, .member].filter { $0 != other }
        default: []
        }
    }
}

/// One finished war (clan-war-history.schema.json).
public struct ClanWarRecord: Codable, Hashable, Sendable, Identifiable {
    public struct Opponent: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var tag: String
    }

    public var id: String
    public var weekStart: String
    public var opponent: Opponent?
    public var us: Int
    public var them: Int
    public var won: Bool?
    public var draw: Bool
    public var reason: String?

    /// W / L / D for the history list.
    public var letter: String { draw ? "D" : won == true ? "W" : "L" }
}

/// War Chests (war-chests.schema.json): earned, fixed content (XP), shown before opening.
public struct WarChests: Codable, Hashable, Sendable {
    public struct Chest: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        /// bronze | silver | gold
        public var tier: String
        public var xp: Int
        public var clanName: String?
        public var weekStart: String?
    }

    public struct Medals: Codable, Hashable, Sendable {
        public var gold: Int
        public var silver: Int
        public var bronze: Int
    }

    public var unopened: [Chest]
    public var medals: Medals
}

public enum WarStreak {
    /// Current streak from the newest war: ("W", 3) = three wins in a row. Draws break a streak.
    public static func current(_ wars: [ClanWarRecord]) -> (letter: String, count: Int)? {
        guard let first = wars.first, !first.draw else { return nil }
        let n = wars.prefix { !$0.draw && $0.letter == first.letter }.count
        return (first.letter, n)
    }
}
