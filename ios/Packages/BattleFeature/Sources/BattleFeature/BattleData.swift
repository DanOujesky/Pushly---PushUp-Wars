import DesignSystem
import Foundation

/// A battle as the caller sees it (battle.schema.json).
public struct Battle: Codable, Hashable, Sendable, Identifiable {
    public struct Opponent: Codable, Hashable, Sendable {
        public var id: String?
        public var username: String
        public var avatarPreset: String?
        public var trophies: Int?
    }

    public struct Pair<T: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        public var a: T
        public var b: T
    }

    public struct Outcome: Codable, Hashable, Sendable {
        public var winner: String?
        public var reason: String
        public var a: BattleRules.Side
        public var b: BattleRules.Side
        public var counted: Bool?
        public var trophies: Pair<Int>?
    }

    public var id: String
    public var type: String
    public var mode: String
    public var variant: [String: Int]
    public var ranked: Bool
    public var status: String
    public var startAt: String?
    /// "a" | "b"
    public var me: String
    public var opponent: Opponent
    public var ready: Pair<Bool>
    public var score: Pair<Int>
    public var result: Outcome?
    /// "me" | "opponent" | nil
    public var winner: String?
    /// Ghost battle: the opponent is a recorded timeline (doc 07 §7).
    public var ghost: Bool?
    /// Practice bot level when the opponent is a labelled bot (D-063); nil for people and recorded ghosts.
    public var bot: String?
    /// Only in the start response of a ghost battle.
    public var ghostTimeline: [BattleRules.Rep]?
    /// ms since start of each side's latest rep (Turns window), migration 0020.
    public var lastRepT: Pair<Int64?>?
    /// Best of 3: reps per round so far (raw counts).
    public var rounds: [Pair<Int>]?

    public var myScore: Int { me == "a" ? score.a : score.b }
    public var theirLastRepT: Int64? { lastRepT.flatMap { me == "a" ? $0.b : $0.a } }
    public var theirRounds: [Int] { (rounds ?? []).map { me == "a" ? $0.b : $0.a } }
    public var theirScore: Int { me == "a" ? score.b : score.a }
    public var myTrophies: Int? { result?.trophies.map { me == "a" ? $0.a : $0.b } }
    public var isOver: Bool { ["settled", "cancelled", "void"].contains(status) }
    /// Opponent name for display: bots always carry the 🤖 so nobody mistakes them for a person.
    public var opponentDisplayName: String { bot == nil ? opponent.username : "🤖 " + opponent.username }
}

/// Practice bot levels (D-063), weakest first.
public enum BotLevel: String, CaseIterable, Sendable, Identifiable {
    case beginner, rookie, athlete, pro, champion
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .beginner: String(localized: "Beginner")
        case .rookie: String(localized: "Rookie")
        case .athlete: String(localized: "Athlete")
        case .pro: String(localized: "Pro")
        case .champion: String(localized: "Champion")
        }
    }

    /// Rough pace shown in the picker.
    public var pace: String {
        switch self {
        case .beginner: String(localized: "~15 reps a minute")
        case .rookie: String(localized: "~22 reps a minute")
        case .athlete: String(localized: "~28 reps a minute")
        case .pro: String(localized: "~36 reps a minute")
        case .champion: String(localized: "~45 reps a minute")
        }
    }
}

public struct BattleInvites: Codable, Hashable, Sendable {
    public struct Incoming: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var from: Battle.Opponent
        public var mode: String
        public var variant: [String: Int]
        public var ranked: Bool
    }

    public struct Outgoing: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var to: Battle.Opponent?
        public var code: String?
        public var mode: String
        public var status: String
        public var battleId: String?
    }

    public var incoming: [Incoming]
    public var outgoing: [Outgoing]
}

public struct MatchmakingStatus: Codable, Hashable, Sendable {
    public var queued: Bool
    public var battle: Battle?
    public var waitedS: Int?
    public var timedOut: Bool?
}

public struct FriendPick: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var username: String
    public var avatarPreset: String?
}

/// Modes offered in the app (doc 07 §2). Quick match: max reps 60 s, speed 20, best of 3; turns and endurance are
/// friend-only.
public enum BattleMode: String, CaseIterable, Sendable, Identifiable {
    case maxReps = "max_reps", speed, bestOf3 = "best_of_3", turns, endurance
    public var id: String { rawValue }

    public var variant: [String: Int] {
        switch self {
        case .maxReps: ["durationS": 60]
        case .speed: ["targetReps": 20]
        case .bestOf3, .turns, .endurance: [:]
        }
    }

    public var quickMatch: Bool { [.maxReps, .speed, .bestOf3].contains(self) }
}

/// Backend calls (JSON of shared/contracts), wired in the app from Networking.
public struct BattleService: Sendable {
    public var invites: @Sendable () async throws -> Data
    public var friends: @Sendable () async throws -> Data
    public var invite: @Sendable (_ toUser: String, _ mode: String, _ ranked: Bool) async throws -> Data
    public var respond: @Sendable (_ inviteId: String, _ accept: Bool) async throws -> Data
    public var join: @Sendable (_ mode: String) async throws -> Data
    public var status: @Sendable () async throws -> Data
    public var leaveQueue: @Sendable () async throws -> Void
    public var get: @Sendable (_ id: String) async throws -> Data
    public var ready: @Sendable (_ id: String) async throws -> Data
    public var push: @Sendable (_ id: String, _ reps: Data) async throws -> Void
    public var finish: @Sendable (_ id: String) async throws -> Data
    public var forfeit: @Sendable (_ id: String) async throws -> Data
    public var history: @Sendable () async throws -> Data
    /// `start_ghost_battle(mode)` — never ranked, 3 a day for free users.
    public var ghost: @Sendable (_ mode: String) async throws -> Data
    /// My archived seasons (season-history.schema.json).
    public var seasons: @Sendable () async throws -> Data
    /// `start_bot_battle(mode, level)` — a labelled practice bot; level nil = the one that fits me.
    public var bot: @Sendable (_ mode: String, _ level: String?) async throws -> Data
    /// Edge Function `battle-token`: LiveKit {url, token, room} for the battle video (doc 07 §5).
    public var videoToken: @Sendable (_ battleId: String) async throws -> Data
    /// `get_battle_stats()` (battle-stats.schema.json): trophies, league, rank, record for the arena header.
    public var stats: @Sendable () async throws -> Data
    /// `search_users(q)` (user-search.schema.json) — add friends from the Friends sheet (D-072).
    public var searchUsers: @Sendable (_ query: String) async throws -> Data
    /// `send_friend_request(user_id)`.
    public var addFriend: @Sendable (_ userId: String) async throws -> Void
    /// `matchmaking_bot()` (D-075): nobody found after 10 s → ranked Arena Bot battle.
    public var arenaBot: @Sendable () async throws -> Data
    /// `get_leaderboard('battles', scope, 'season')` — the trophy board (leaderboard.schema.json).
    public var trophyBoard: @Sendable (_ scope: String) async throws -> Data
    /// `get_clan_leaderboard('rating')` (clan-leaderboard.schema.json).
    public var clanBoard: @Sendable () async throws -> Data

    public init(invites: @escaping @Sendable () async throws -> Data, friends: @escaping @Sendable () async throws -> Data,
                invite: @escaping @Sendable (String, String, Bool) async throws -> Data,
                respond: @escaping @Sendable (String, Bool) async throws -> Data,
                join: @escaping @Sendable (String) async throws -> Data, status: @escaping @Sendable () async throws -> Data,
                leaveQueue: @escaping @Sendable () async throws -> Void, get: @escaping @Sendable (String) async throws -> Data,
                ready: @escaping @Sendable (String) async throws -> Data, push: @escaping @Sendable (String, Data) async throws -> Void,
                finish: @escaping @Sendable (String) async throws -> Data, forfeit: @escaping @Sendable (String) async throws -> Data,
                history: @escaping @Sendable () async throws -> Data,
                ghost: @escaping @Sendable (String) async throws -> Data,
                seasons: @escaping @Sendable () async throws -> Data = { Data("[]".utf8) },
                bot: @escaping @Sendable (String, String?) async throws -> Data = { _, _ in throw CancellationError() },
                videoToken: @escaping @Sendable (String) async throws -> Data = { _ in throw CancellationError() },
                stats: @escaping @Sendable () async throws -> Data = { throw CancellationError() },
                searchUsers: @escaping @Sendable (String) async throws -> Data = { _ in Data("[]".utf8) },
                addFriend: @escaping @Sendable (String) async throws -> Void = { _ in throw CancellationError() },
                arenaBot: @escaping @Sendable () async throws -> Data = { throw CancellationError() },
                trophyBoard: @escaping @Sendable (String) async throws -> Data = { _ in throw CancellationError() },
                clanBoard: @escaping @Sendable () async throws -> Data = { throw CancellationError() }) {
        self.arenaBot = arenaBot
        self.trophyBoard = trophyBoard
        self.clanBoard = clanBoard
        self.stats = stats
        self.searchUsers = searchUsers
        self.addFriend = addFriend
        self.bot = bot
        self.videoToken = videoToken
        self.ghost = ghost
        self.seasons = seasons
        self.invites = invites
        self.friends = friends
        self.invite = invite
        self.respond = respond
        self.join = join
        self.status = status
        self.leaveQueue = leaveQueue
        self.get = get
        self.ready = ready
        self.push = push
        self.finish = finish
        self.forfeit = forfeit
        self.history = history
    }
}

/// The arena header of the Battle tab (D-071): the part of `get_battle_stats()` it shows.
public struct ArenaStatus: Codable, Equatable, Sendable {
    public struct Next: Codable, Equatable, Sendable {
        public var at: Int
        public var league: String
        public var tier: String?
    }

    public struct Record: Codable, Equatable, Sendable {
        public var wins: Int
        public var losses: Int
        public var draws: Int
        public var winStreak: Int
        public var bestWinStreak: Int
    }

    public var trophies: Int
    public var bestTrophies: Int
    public var league: String
    public var tier: String?
    public var next: Next?
    public var rank: Int?
    public var seasonEndsAt: String?
    public var record: Record
    /// The closest players above me (up to 3), for the ladder.
    public var targets: [Target]?

    public struct Target: Codable, Equatable, Sendable, Identifiable {
        public var userId: String
        public var username: String
        public var avatarPreset: String?
        public var trophies: Int
        public var gap: Int
        public var id: String { userId }
    }

    /// Tier steps (same list as get_battle_stats, migration 0026).
    static let steps = [0, 200, 400, 600, 800, 1000, 1200, 1466, 1732, 2000, 2333, 2666, 3000, 3333, 3666, 4000, 5000]

    /// 0…1 from the current tier's start to the next step.
    public var progress: Double {
        guard let next else { return 1 }
        let start = Self.steps.last(where: { $0 <= trophies }) ?? 0
        return min(1, max(0, Double(trophies - start) / Double(max(next.at - start, 1))))
    }

    public func seasonDaysLeft(now: Date = Date()) -> Int? {
        guard let s = seasonEndsAt, let end = ISO8601DateFormatter().date(from: s) else { return nil }
        return max(0, Int(ceil(end.timeIntervalSince(now) / 86400)))
    }
}

/// Every league and tier with its trophy range (doc 08 §2.2) — the ladder sheet (D-072). `leagueFor` matches the
/// server's `app.league_for` and shared/test-vectors/trophies/leagues.json.
public enum LeagueLadder {
    public struct Rung: Equatable, Sendable, Identifiable {
        public let league: String
        public let tier: String?
        public let from: Int
        /// Last trophy count of this rung; nil for Legend (no top).
        public let to: Int?
        public var id: String { league + (tier ?? "") }
    }

    /// Reaching one of these keeps you from dropping below it until the season ends (doc 08 §2.3).
    public static let floors: Set<Int> = [600, 1200, 2000]

    static let leagues: [(name: String, lo: Int, hi: Int)] = [
        ("bronze", 0, 599), ("silver", 600, 1199), ("gold", 1200, 1999),
        ("platinum", 2000, 2999), ("diamond", 3000, 3999), ("champion", 4000, 4999),
    ]

    /// All rungs from Bronze III up to Legend.
    public static let rungs: [Rung] = {
        var out: [Rung] = []
        for l in leagues {
            if l.name == "champion" {
                out.append(Rung(league: l.name, tier: nil, from: l.lo, to: l.hi))
                continue
            }
            let size = (l.hi - l.lo + 1) / 3
            out.append(Rung(league: l.name, tier: "III", from: l.lo, to: l.lo + size - 1))
            out.append(Rung(league: l.name, tier: "II", from: l.lo + size, to: l.lo + 2 * size - 1))
            out.append(Rung(league: l.name, tier: "I", from: l.lo + 2 * size, to: l.hi))
        }
        out.append(Rung(league: "legend", tier: nil, from: 5000, to: nil))
        return out
    }()

    public static func leagueFor(_ trophies: Int) -> (league: String, tier: String?) {
        let t = max(0, trophies)
        let rung = rungs.last(where: { $0.from <= t }) ?? rungs[0]
        return (rung.league, rung.tier)
    }

    public static func rung(for trophies: Int) -> Rung {
        rungs.last(where: { $0.from <= max(0, trophies) }) ?? rungs[0]
    }
}

/// A user found by username (user-search.schema.json) with their relation to me.
public struct UserHit: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var username: String
    public var avatarPreset: String?
    /// none | friends | incoming | outgoing
    public var relation: String?
}

/// One archived season (season-history.schema.json): the badge is the best league reached.
public struct SeasonResult: Codable, Hashable, Sendable, Identifiable {
    public var seasonId: Int
    public var month: String
    public var finalTrophies: Int
    public var bestTrophies: Int
    public var league: String
    public var tier: String?
    public var rank: Int
    public var id: Int { seasonId }
}

public extension BattleMode {
    /// Mode for a wire name (rematch keeps the mode of the battle).
    init?(wire: String) { self.init(rawValue: wire) }
}

/// The trophy leaderboard (`get_leaderboard('battles', scope, 'season')`, leaderboard.schema.json).
public struct TrophyBoard: Decodable, Sendable, Equatable {
    public struct User: Decodable, Sendable, Equatable {
        public var id: String?
        public var username: String?
        public var avatarPreset: String?
        public var country: String?
        public var anonymous: Bool?
        public var pro: Bool?
        public var frame: String?
    }

    public struct Row: Decodable, Sendable, Equatable, Identifiable {
        public var rank: Int
        public var score: Int
        public var isMe: Bool
        public var user: User
        public var id: String { "\(rank)-\(user.id ?? "anon")-\(score)" }
    }

    public struct Me: Decodable, Sendable, Equatable {
        public var rank: Int
        public var score: Int
        public var shadow: Bool
    }

    public var rows: [Row]
    public var me: Me?
    public var around: [Row]?
}

/// One row of `get_clan_leaderboard('rating')` (clan-leaderboard.schema.json).
public struct ClanBoardRow: Decodable, Sendable, Equatable, Identifiable {
    public struct Clan: Decodable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var tag: String
        public var badge: ClanBadgeStyle?
        public var memberCount: Int
    }

    public var rank: Int
    public var score: Int
    public var isMine: Bool
    public var clan: Clan
    public var id: String { clan.id }
}
