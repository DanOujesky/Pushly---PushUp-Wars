import Foundation

/// Who can see a profile (doc 02 PS-73). Raw values match the Postgres enum `visibility_t`.
public enum ProfileVisibility: String, Codable, Sendable, CaseIterable {
    case `public`, friends, `private`
}

/// The signed-in user's own profile row (`public.profiles`, doc 11 §2). Fixture: shared/contracts/fixtures/profile.json
public struct Profile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var username: String
    public var onboardingCompleted: Bool
    public var avatarPreset: String?
    public var avatarPath: String?
    public var country: String?
    public var birthYear: Int?
    public var timezone: String
    public var profileVisibility: ProfileVisibility
    public var leaderboardVisible: Bool
    public var trophies: Int
    public var xp: Int
    public var level: Int
    public var isPro: Bool
    /// Pro profile frame (D-074); shown only while Pro.
    public var frame: String?

    enum CodingKeys: String, CodingKey {
        case id, username, country, timezone, trophies, xp, level, frame
        case onboardingCompleted = "onboarding_completed"
        case avatarPreset = "avatar_preset"
        case avatarPath = "avatar_path"
        case birthYear = "birth_year"
        case profileVisibility = "profile_visibility"
        case leaderboardVisible = "leaderboard_visible"
        case isPro = "is_pro"
    }

    public init(
        id: UUID, username: String, onboardingCompleted: Bool, avatarPreset: String? = nil, avatarPath: String? = nil,
        country: String? = nil, birthYear: Int? = nil, timezone: String = "UTC",
        profileVisibility: ProfileVisibility = .public, leaderboardVisible: Bool = true,
        trophies: Int = 0, xp: Int = 0, level: Int = 1, isPro: Bool = false, frame: String? = nil
    ) {
        self.frame = frame
        self.id = id
        self.username = username
        self.onboardingCompleted = onboardingCompleted
        self.avatarPreset = avatarPreset
        self.avatarPath = avatarPath
        self.country = country
        self.birthYear = birthYear
        self.timezone = timezone
        self.profileVisibility = profileVisibility
        self.leaderboardVisible = leaderboardVisible
        self.trophies = trophies
        self.xp = xp
        self.level = level
        self.isPro = isPro
    }
}

/// Fields accepted by RPC `update_profile(patch)`. Nil fields are omitted from the JSON (not sent).
public struct ProfilePatch: Encodable, Sendable, Equatable {
    public var username: String?
    public var avatarPreset: String?
    public var country: String?
    public var birthYear: Int?
    public var timezone: String?
    public var profileVisibility: ProfileVisibility?
    public var leaderboardVisible: Bool?

    public init(
        username: String? = nil, avatarPreset: String? = nil, country: String? = nil, birthYear: Int? = nil,
        timezone: String? = nil, profileVisibility: ProfileVisibility? = nil, leaderboardVisible: Bool? = nil
    ) {
        self.username = username
        self.avatarPreset = avatarPreset
        self.country = country
        self.birthYear = birthYear
        self.timezone = timezone
        self.profileVisibility = profileVisibility
        self.leaderboardVisible = leaderboardVisible
    }

    enum CodingKeys: String, CodingKey {
        case username, country, timezone
        case avatarPreset = "avatar_preset"
        case birthYear = "birth_year"
        case profileVisibility = "profile_visibility"
        case leaderboardVisible = "leaderboard_visible"
    }

    public var isEmpty: Bool { self == ProfilePatch() }
}

/// Remote config (`public.app_config`, doc 03 §7) reduced to what the app uses.
public struct RemoteConfig: Sendable, Equatable {
    public var minSupportedVersion: String
    public var killSwitches: [String: Bool]

    public init(minSupportedVersion: String = "0.0.0", killSwitches: [String: Bool] = [:]) {
        self.minSupportedVersion = minSupportedVersion
        self.killSwitches = killSwitches
    }

    public static let fallback = RemoteConfig()

    /// Builds the config from `app_config` rows for one platform ("ios").
    public init(rows: [AppConfigRow], platform: String) {
        var config = RemoteConfig()
        for row in rows {
            switch row.key {
            case "min_supported_version":
                if case let .object(dict) = row.value, case let .string(v)? = dict[platform] { config.minSupportedVersion = v }
            case "kill_switches":
                if case let .object(dict) = row.value {
                    for (k, v) in dict { if case let .bool(b) = v { config.killSwitches[k] = b } }
                }
            default:
                break
            }
        }
        self = config
    }
}

public struct AppConfigRow: Decodable, Sendable, Equatable {
    public let key: String
    public let value: JSONValue
}

/// Minimal JSON value for loosely typed config payloads.
public enum JSONValue: Decodable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
}
