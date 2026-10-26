import DesignSystem
import Foundation

/// A clan in lists (clan-summary.schema.json).
public struct ClanSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var tag: String
    /// Shape + colour + emblem (D-074); `{}` for clans that never picked one.
    public var badge: ClanBadgeStyle?
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
    /// Pushly Pro — PRO badge (D-073).
    public var pro: Bool?
    /// Pro profile frame (D-074).
    public var frame: String?
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
    /// Clan Wars v2 (D-078): the lobby / live war and the latest result.
    public var warState: ClanWarState?

    /// The war on screen right now: lobby or live.
    public var war: ClanWar? { warState?.current }

    enum CodingKeys: String, CodingKey { case members, requests, warState }

    public init(from decoder: Decoder) throws {
        summary = try ClanSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        members = try c.decode([Member].self, forKey: .members)
        requests = try c.decode([Request].self, forKey: .requests)
        warState = try c.decodeIfPresent(ClanWarState.self, forKey: .warState)
    }

    public func encode(to encoder: Encoder) throws {
        try summary.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(members, forKey: .members)
        try c.encode(requests, forKey: .requests)
        try c.encodeIfPresent(warState, forKey: .warState)
    }
}

/// `get_clan_war_state()` (clan-war-state.schema.json, D-078): the lobby or live war, and the latest finished war —
/// shown first as the result screen until the player has seen it.
public struct ClanWarState: Codable, Hashable, Sendable {
    public var current: ClanWar?
    public var last: ClanWar?
}

/// One Clan War of 2–4 clans (D-078): lobby → live (Mon 00:00 UTC) → finished (Sun 20:00 UTC).
public struct ClanWar: Codable, Hashable, Sendable {
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

    public struct Stakes: Codable, Hashable, Sendable {
        /// Clan trophies for finishing 1st.
        public var win: Int
        /// Clan trophies for finishing last (negative).
        public var last: Int
    }

    /// One clan in the war, in standings order.
    public struct Standing: Codable, Hashable, Sendable, Identifiable {
        public var clan: ClanSummary
        public var score: Int
        public var isMine: Bool
        public var rank: Int?
        /// Clan trophies won / lost (finished only).
        public var ratingDelta: Int?
        /// What 1st / last would bring (lobby + live).
        public var stakes: Stakes?
        public var mvp: MemberCard?
        public var id: String { clan.id }
    }

    public struct FeedItem: Codable, Hashable, Sendable {
        public var clanId: String
        public var clanName: String
        public var mine: Bool
        public var username: String
        public var points: Int
        public var at: String
    }

    public struct Rally: Codable, Hashable, Sendable {
        public var available: Bool
        public var nextAt: String?
    }

    public struct Result: Codable, Hashable, Sendable {
        public var rank: Int
        public var of: Int
        public var ratingDelta: Int
    }

    public var id: String
    /// lobby | live | finished
    public var status: String
    public var weekStart: String
    public var startsAt: String
    public var endsAt: String
    public var movedWeeks: Int
    public var clans: [Standing]
    public var result: Result?
    public var myToday: Today
    public var top: [Top]
    public var feed: [FeedItem]
    public var rally: Rally?

    public var isLobby: Bool { status == "lobby" }
    public var isLive: Bool { status == "live" }
    public var isFinished: Bool { status == "finished" }
    public var mine: Standing? { clans.first(where: \.isMine) }
    public var rivals: [Standing] { clans.filter { !$0.isMine } }

    /// My score minus the best other clan (positive = I lead).
    public var gap: Int {
        let best = rivals.map(\.score).max() ?? 0
        return (mine?.score ?? 0) - best
    }

    /// My place right now (live) or final (finished).
    public var myRank: Int? { mine?.rank }
}

/// One finished war of my clan (clan-war-results.schema.json, D-078).
public struct ClanWarResult: Codable, Hashable, Sendable, Identifiable {
    public struct Clan: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var tag: String
        public var badge: ClanBadgeStyle?
        public var score: Int
        public var rank: Int?
        public var isMine: Bool
    }

    public var id: String
    public var weekStart: String
    public var rank: Int
    public var of: Int
    public var score: Int
    public var ratingDelta: Int
    public var clans: [Clan]

    /// W = 1st of a real war, L otherwise.
    public var letter: String { rank == 1 && of > 1 ? "W" : "L" }
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
    /// Current streak from the newest war: ("W", 3) = three wins (1st places) in a row.
    public static func current(_ wars: [ClanWarResult]) -> (letter: String, count: Int)? {
        guard let first = wars.first else { return nil }
        let n = wars.prefix { $0.letter == first.letter }.count
        return (first.letter, n)
    }
}
