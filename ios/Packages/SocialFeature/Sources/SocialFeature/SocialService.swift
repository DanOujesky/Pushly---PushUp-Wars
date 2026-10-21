import Foundation

/// What the social screens need from the backend; JSON in and out (shared/contracts). Implemented by Networking's
/// `SupabaseBackend` and wired in the app, so this package doesn't depend on Networking.
public struct SocialService: Sendable {
    public var listFriends: @Sendable () async throws -> Data
    public var search: @Sendable (_ query: String) async throws -> Data
    public var sendRequest: @Sendable (_ userId: String) async throws -> String
    public var respond: @Sendable (_ userId: String, _ accept: Bool) async throws -> String
    public var remove: @Sendable (_ userId: String) async throws -> String
    public var block: @Sendable (_ userId: String) async throws -> String
    public var unblock: @Sendable (_ userId: String) async throws -> String
    public var feed: @Sendable () async throws -> Data
    public var kudos: @Sendable (_ eventId: Int) async throws -> Int
    public var leaderboard: @Sendable (_ board: String, _ scope: String, _ period: String) async throws -> Data
    /// `get_user_profile(user_id, username)` (user-profile.schema.json, JSON null when not found).
    public var profile: @Sendable (_ userId: String?, _ username: String?) async throws -> Data

    public init(
        listFriends: @escaping @Sendable () async throws -> Data,
        search: @escaping @Sendable (String) async throws -> Data,
        sendRequest: @escaping @Sendable (String) async throws -> String,
        respond: @escaping @Sendable (String, Bool) async throws -> String,
        remove: @escaping @Sendable (String) async throws -> String,
        block: @escaping @Sendable (String) async throws -> String,
        unblock: @escaping @Sendable (String) async throws -> String,
        feed: @escaping @Sendable () async throws -> Data,
        kudos: @escaping @Sendable (Int) async throws -> Int,
        leaderboard: @escaping @Sendable (String, String, String) async throws -> Data,
        profile: @escaping @Sendable (String?, String?) async throws -> Data = { _, _ in Data("null".utf8) }
    ) {
        self.profile = profile
        self.listFriends = listFriends
        self.search = search
        self.sendRequest = sendRequest
        self.respond = respond
        self.remove = remove
        self.block = block
        self.unblock = unblock
        self.feed = feed
        self.kudos = kudos
        self.leaderboard = leaderboard
    }
}
