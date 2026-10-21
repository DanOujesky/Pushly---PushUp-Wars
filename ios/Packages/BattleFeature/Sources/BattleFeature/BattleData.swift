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

    public init(invites: @escaping @Sendable () async throws -> Data, friends: @escaping @Sendable () async throws -> Data,
                invite: @escaping @Sendable (String, String, Bool) async throws -> Data,
                respond: @escaping @Sendable (String, Bool) async throws -> Data,
                join: @escaping @Sendable (String) async throws -> Data, status: @escaping @Sendable () async throws -> Data,
                leaveQueue: @escaping @Sendable () async throws -> Void, get: @escaping @Sendable (String) async throws -> Data,
                ready: @escaping @Sendable (String) async throws -> Data, push: @escaping @Sendable (String, Data) async throws -> Void,
                finish: @escaping @Sendable (String) async throws -> Data, forfeit: @escaping @Sendable (String) async throws -> Data,
                history: @escaping @Sendable () async throws -> Data,
                ghost: @escaping @Sendable (String) async throws -> Data,
                seasons: @escaping @Sendable () async throws -> Data = { Data("[]".utf8) }) {
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
