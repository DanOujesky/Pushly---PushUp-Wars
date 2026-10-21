import Core
import Foundation
import Supabase

/// Real backend implementation on top of supabase-swift. The only file that imports `Supabase`,
/// so the SDK can be swapped or mocked without touching features.
public final class SupabaseBackend: AuthServicing, ProfileServicing, RemoteConfigServicing, AlarmSyncServicing,
    RepSessionServicing, StatsServicing, SocialServicing, ClanServicing, AccountServicing, BattleServicing, Sendable {
    private let client: SupabaseClient

    public init(config: BackendConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    // MARK: Auth

    public func currentUserID() async -> UUID? {
        do {
            return try await client.auth.session.user.id
        } catch {
            return nil
        }
    }

    public func authStateChanges() -> AsyncStream<UUID?> {
        let auth = client.auth
        return AsyncStream { continuation in
            let task = Task {
                for await change in auth.authStateChanges {
                    continuation.yield(change.session?.user.id)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func sendEmailCode(to email: String) async throws {
        try await mapErrors {
            try await client.auth.signInWithOTP(email: email, redirectTo: AuthCallback.url, shouldCreateUser: true)
        }
    }

    public func verifyEmailCode(email: String, code: String) async throws -> UUID {
        try await mapErrors {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            guard let user = response.session?.user else {
                throw AppError(code: .unauthenticated, message: "No session after verification")
            }
            return user.id
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        try await mapErrors {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return session.user.id
        }
    }

    public func handleAuthCallback(_ url: URL) async throws -> UUID {
        try await mapErrors {
            try await client.auth.session(from: url).user.id
        }
    }

    public func signOut() async throws {
        try await mapErrors { try await client.auth.signOut() }
    }

    // MARK: Profile

    public func fetchOwnProfile() async throws -> Profile {
        try await mapErrors {
            let uid = try await client.auth.session.user.id
            return try await client.from("profiles").select().eq("id", value: uid).single().execute().value
        }
    }

    public func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        struct Params: Encodable, Sendable { let patch: ProfilePatch }
        return try await mapErrors {
            try await client.rpc("update_profile", params: Params(patch: patch)).single().execute().value
        }
    }

    public func isUsernameAvailable(_ name: String) async throws -> Bool {
        struct Params: Encodable, Sendable { let name: String }
        return try await mapErrors {
            try await client.rpc("username_available", params: Params(name: name)).execute().value
        }
    }

    // MARK: Remote config

    public func fetch() async throws -> RemoteConfig {
        try await mapErrors {
            let rows: [AppConfigRow] = try await client.from("app_config").select("key,value").execute().value
            return RemoteConfig(rows: rows, platform: "ios")
        }
    }

    // MARK: Alarm sync (P2-09)

    public func syncAlarms(_ changes: Data) async throws -> Data {
        try await mapErrors {
            struct Params: Encodable, Sendable { let changes: AnyJSON }
            let json = try JSONDecoder().decode(AnyJSON.self, from: changes)
            return try await client.rpc("sync_alarms", params: Params(changes: json)).execute().data
        }
    }

    // MARK: Rep sessions (P4-03/P4-05)

    public func submitRepSession(_ log: Data) async throws -> Data {
        try await mapErrors {
            try await client.functions.invoke("submit-rep-session", options: FunctionInvokeOptions(body: log)) { data, _ in
                data
            }
        }
    }

    public func wakeSummary() async throws -> Data {
        try await mapErrors { try await client.rpc("get_wake_summary").execute().data }
    }

    /// `get_stats(period)` — shared/contracts/stats.schema.json.
    public func stats(period: String) async throws -> Data {
        try await mapErrors { try await client.rpc("get_stats", params: ["period": period]).execute().data }
    }

    /// `get_achievements()` — shared/contracts/achievements.schema.json.
    public func achievements() async throws -> Data {
        try await mapErrors { try await client.rpc("get_achievements").execute().data }
    }

    // MARK: Social (migration 0011)

    public func listFriends() async throws -> Data {
        try await mapErrors { try await client.rpc("list_friends").execute().data }
    }

    public func searchUsers(_ query: String) async throws -> Data {
        try await mapErrors { try await client.rpc("search_users", params: ["q": query]).execute().data }
    }

    public func sendFriendRequest(_ userId: String) async throws -> String {
        try await mapErrors { try await client.rpc("send_friend_request", params: ["target": userId]).execute().value }
    }

    public func respondFriendRequest(_ userId: String, accept: Bool) async throws -> String {
        struct Params: Encodable, Sendable { let requester: String; let accept: Bool }
        return try await mapErrors {
            try await client.rpc("respond_friend_request", params: Params(requester: userId, accept: accept)).execute().value
        }
    }

    public func removeFriend(_ userId: String) async throws -> String {
        try await mapErrors { try await client.rpc("remove_friend", params: ["target": userId]).execute().value }
    }

    public func blockUser(_ userId: String) async throws -> String {
        try await mapErrors { try await client.rpc("block_user", params: ["target": userId]).execute().value }
    }

    public func unblockUser(_ userId: String) async throws -> String {
        try await mapErrors { try await client.rpc("unblock_user", params: ["target": userId]).execute().value }
    }

    public func friendFeed() async throws -> Data {
        try await mapErrors { try await client.rpc("get_friend_feed").execute().data }
    }

    public func giveKudos(_ eventId: Int) async throws -> Int {
        try await mapErrors { try await client.rpc("give_kudos", params: ["event_id": eventId]).execute().value }
    }

    public func leaderboard(board: String, scope: String, period: String) async throws -> Data {
        try await mapErrors {
            try await client.rpc("get_leaderboard", params: ["board": board, "scope": scope, "period": period]).execute().data
        }
    }

    // MARK: Clans (migration 0015)

    private struct ClanIdParams: Encodable, Sendable {
        let clanId: String?
        enum CodingKeys: String, CodingKey { case clanId = "clan_id" }
    }

    public func myClan() async throws -> Data {
        try await mapErrors { try await client.rpc("get_clan", params: ClanIdParams(clanId: nil)).execute().data }
    }

    public func clan(_ id: String) async throws -> Data {
        try await mapErrors { try await client.rpc("get_clan", params: ClanIdParams(clanId: id)).execute().data }
    }

    public func searchClans(_ query: String) async throws -> Data {
        try await mapErrors { try await client.rpc("search_clans", params: ["q": query]).execute().data }
    }

    public func createClan(name: String, tag: String, description: String, joinPolicy: String) async throws -> Data {
        try await mapErrors {
            try await client.rpc("create_clan", params: ["name": name, "tag": tag, "description": description,
                                                         "join_policy": joinPolicy]).execute().data
        }
    }

    public func joinClan(_ id: String, message: String?) async throws -> String {
        struct Params: Encodable, Sendable {
            let clanId: String
            let message: String?
            enum CodingKeys: String, CodingKey { case clanId = "clan_id", message }
        }
        return try await mapErrors { try await client.rpc("join_clan", params: Params(clanId: id, message: message)).execute().value }
    }

    public func respondClanRequest(_ userId: String, accept: Bool) async throws -> String {
        struct Params: Encodable, Sendable {
            let userId: String
            let accept: Bool
            enum CodingKeys: String, CodingKey { case userId = "user_id", accept }
        }
        return try await mapErrors {
            try await client.rpc("respond_clan_request", params: Params(userId: userId, accept: accept)).execute().value
        }
    }

    public func leaveClan() async throws -> String {
        try await mapErrors { try await client.rpc("leave_clan").execute().value }
    }

    public func kickMember(_ userId: String) async throws {
        _ = try await mapErrors { try await client.rpc("kick_member", params: ["user_id": userId]).execute().data }
    }

    public func setMemberRole(_ userId: String, role: String) async throws {
        _ = try await mapErrors { try await client.rpc("set_member_role", params: ["user_id": userId, "role": role]).execute().data }
    }

    public func transferLeadership(_ userId: String) async throws {
        _ = try await mapErrors { try await client.rpc("transfer_leadership", params: ["user_id": userId]).execute().data }
    }

    public func clanMessages(before: Int?) async throws -> Data {
        struct Params: Encodable, Sendable {
            let beforeId: Int?
            let lim: Int
            enum CodingKeys: String, CodingKey { case beforeId = "before_id", lim }
        }
        return try await mapErrors {
            try await client.rpc("get_clan_messages", params: Params(beforeId: before, lim: 100)).execute().data
        }
    }

    public func sendClanMessage(_ body: String, kind: String) async throws {
        _ = try await mapErrors { try await client.rpc("send_clan_message", params: ["body": body, "kind": kind]).execute().data }
    }

    public func clanWarHistory(_ clanId: String?) async throws -> Data {
        struct Params: Encodable, Sendable {
            let clanId: String?
            let lim: Int
            enum CodingKeys: String, CodingKey { case clanId = "clan_id", lim }
        }
        return try await mapErrors {
            try await client.rpc("get_clan_war_history", params: Params(clanId: clanId, lim: 20)).execute().data
        }
    }

    public func warChests() async throws -> Data {
        try await mapErrors { try await client.rpc("get_war_chests").execute().data }
    }

    public func openChest(_ id: String) async throws -> Data {
        try await mapErrors { try await client.rpc("open_chest", params: ["chest_id": id]).execute().data }
    }

    // MARK: Account (migration 0016)

    public func exportMyData() async throws -> Data {
        try await mapErrors { try await client.rpc("export_my_data").execute().data }
    }

    public func deleteMyAccount() async throws {
        _ = try await mapErrors { try await client.rpc("delete_my_account").execute().data }
        try? await client.auth.signOut()
    }

    public func notificationPrefs() async throws -> Data {
        struct Row: Decodable, Sendable { let prefs: AnyJSON }
        return try await mapErrors {
            let rows: [Row] = try await client.from("notification_prefs").select("prefs").execute().value
            return try JSONEncoder().encode(rows.first?.prefs ?? AnyJSON.object([:]))
        }
    }

    public func setNotificationPrefs(_ prefs: Data) async throws -> Data {
        struct Params: Encodable, Sendable { let p: AnyJSON }
        return try await mapErrors {
            let json = try JSONDecoder().decode(AnyJSON.self, from: prefs)
            return try await client.rpc("set_notification_prefs", params: Params(p: json)).execute().data
        }
    }

    public func privacySettings() async throws -> Data {
        try await mapErrors { try await client.rpc("get_privacy_settings").execute().data }
    }

    public func setGhostOptOut(_ optOut: Bool) async throws {
        struct Params: Encodable, Sendable {
            let optOut: Bool
            enum CodingKeys: String, CodingKey { case optOut = "opt_out" }
        }
        try await mapErrors { _ = try await client.rpc("set_ghost_opt_out", params: Params(optOut: optOut)).execute() }
    }

    // MARK: Battles (migration 0014)

    private struct BattleIdParams: Encodable, Sendable {
        let battleId: String
        enum CodingKeys: String, CodingKey { case battleId = "battle_id" }
    }

    public func battleInvites() async throws -> Data {
        try await mapErrors { try await client.rpc("list_battle_invites").execute().data }
    }

    public func createBattleInvite(toUser: String, mode: String, ranked: Bool) async throws -> Data {
        struct Params: Encodable, Sendable {
            let toUser: String
            let mode: String
            let ranked: Bool
            enum CodingKeys: String, CodingKey { case toUser = "to_user", mode, ranked }
        }
        return try await mapErrors {
            try await client.rpc("create_battle_invite", params: Params(toUser: toUser, mode: mode, ranked: ranked)).execute().data
        }
    }

    public func respondBattleInvite(_ id: String, accept: Bool) async throws -> Data {
        struct Params: Encodable, Sendable {
            let inviteId: String
            let accept: Bool
            enum CodingKeys: String, CodingKey { case inviteId = "invite_id", accept }
        }
        return try await mapErrors {
            try await client.rpc("respond_battle_invite", params: Params(inviteId: id, accept: accept)).execute().data
        }
    }

    public func matchmakingJoin(mode: String) async throws -> Data {
        try await mapErrors { try await client.rpc("matchmaking_join", params: ["mode": mode]).execute().data }
    }

    public func matchmakingStatus() async throws -> Data {
        try await mapErrors { try await client.rpc("matchmaking_status").execute().data }
    }

    public func matchmakingLeave() async throws {
        _ = try await mapErrors { try await client.rpc("matchmaking_leave").execute().data }
    }

    public func battle(_ id: String) async throws -> Data {
        try await mapErrors { try await client.rpc("get_battle", params: BattleIdParams(battleId: id)).execute().data }
    }

    public func battleReady(_ id: String) async throws -> Data {
        try await mapErrors { try await client.rpc("battle_ready", params: BattleIdParams(battleId: id)).execute().data }
    }

    public func battlePushReps(_ id: String, reps: Data) async throws {
        struct Params: Encodable, Sendable {
            let battleId: String
            let reps: AnyJSON
            enum CodingKeys: String, CodingKey { case battleId = "battle_id", reps }
        }
        _ = try await mapErrors {
            let json = try JSONDecoder().decode(AnyJSON.self, from: reps)
            return try await client.rpc("battle_push_rep", params: Params(battleId: id, reps: json)).execute().data
        }
    }

    public func battleFinish(_ id: String) async throws -> Data {
        try await mapErrors { try await client.rpc("battle_finish", params: BattleIdParams(battleId: id)).execute().data }
    }

    public func battleForfeit(_ id: String) async throws -> Data {
        try await mapErrors { try await client.rpc("battle_forfeit", params: BattleIdParams(battleId: id)).execute().data }
    }

    public func battleHistory() async throws -> Data {
        try await mapErrors { try await client.rpc("battle_history").execute().data }
    }

    public func startGhostBattle(mode: String) async throws -> Data {
        try await mapErrors { try await client.rpc("start_ghost_battle", params: ["mode": mode]).execute().data }
    }

    public func registerDevice(_ request: Data) async throws -> String {
        struct Params: Encodable, Sendable { let p: AnyJSON }
        return try await mapErrors {
            let json = try JSONDecoder().decode(AnyJSON.self, from: request)
            return try await client.rpc("register_device", params: Params(p: json)).execute().value
        }
    }

    public func serverTimeMs() async throws -> Int64 {
        struct Health: Decodable { let serverMs: Int64 }
        return try await mapErrors {
            try await client.functions.invoke("health", options: FunctionInvokeOptions(method: .get)) { data, _ in
                try JSONDecoder().decode(Health.self, from: data).serverMs
            }
        }
    }

    // MARK: Errors

    private func mapErrors<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as AppError {
            throw error
        } catch {
            throw BackendErrorMapper.map(error)
        }
    }
}

/// Maps SDK / transport errors to `AppError` (doc 12 error codes). Pure — unit tested.
public enum BackendErrorMapper {
    public static func map(_ error: Error) -> AppError {
        if let urlError = error as? URLError {
            return AppError(code: .network, message: urlError.localizedDescription)
        }
        if case let FunctionsError.httpError(status, data) = error {
            return map(httpStatus: status, body: data)
        }
        let text = String(describing: error)
        return map(postgresCode: postgresCode(in: text), message: text)
    }

    /// Postgres SQLSTATEs raised by our RPCs (migration 0002) → app error codes.
    public static func map(postgresCode: String?, message: String) -> AppError {
        switch postgresCode {
        case "23505": AppError(code: .conflict, message: "taken")
        case "22023", "P0001": AppError(code: .validationFailed, message: message)
        case "28000", "42501": AppError(code: .forbidden, message: message)
        case "P0002": AppError(code: .notFound, message: message)
        default: AppError(code: .unknown, message: message)
        }
    }

    /// Edge Function errors: `{ "error": { "code", "message", "retryable" } }` (doc 12); falls back to the status.
    public static func map(httpStatus: Int, body: Data) -> AppError {
        struct Envelope: Decodable {
            struct Inner: Decodable { let code: String; let message: String?; let retryable: Bool? }
            let error: Inner
        }
        if let e = try? JSONDecoder().decode(Envelope.self, from: body), let code = AppErrorCode(rawValue: e.error.code) {
            return AppError(code: code, message: e.error.message ?? code.rawValue, retryable: e.error.retryable)
        }
        let code: AppErrorCode = switch httpStatus {
        case 401: .unauthenticated
        case 403: .forbidden
        case 404: .notFound
        case 409: .conflict
        case 422, 400: .validationFailed
        case 426: .upgradeRequired
        case 429: .rateLimited
        default: httpStatus >= 500 ? .internal : .unknown
        }
        return AppError(code: code, message: "HTTP \(httpStatus)")
    }

    static func postgresCode(in text: String) -> String? {
        for code in ["23505", "22023", "P0001", "28000", "42501", "P0002"] where text.contains(code) {
            return code
        }
        return nil
    }
}
