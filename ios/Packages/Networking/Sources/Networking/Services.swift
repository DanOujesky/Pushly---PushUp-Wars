import Core
import Foundation

/// Authentication (doc 02 PS-02). Implementations: `SupabaseBackend` (real), fakes in tests.
public protocol AuthServicing: Sendable {
    /// The signed-in user, if a valid session exists (restored from the keychain on launch).
    func currentUserID() async -> UUID?
    /// Emits the user id whenever the auth state changes (nil = signed out).
    func authStateChanges() -> AsyncStream<UUID?>
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws -> UUID
    func signInWithApple(idToken: String, nonce: String) async throws -> UUID
    /// Google ID token from the native Google sign-in (Supabase provider "google", nonce checks skipped — D-061).
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> UUID
    func signOut() async throws
    /// Completes a sign-in from an email link (`pushly://auth-callback?...`). Returns the signed-in user.
    func handleAuthCallback(_ url: URL) async throws -> UUID
}

public enum AuthCallback {
    /// Redirect target of sign-in emails. Must be in Supabase `additional_redirect_urls` (supabase/config.toml).
    public static let url: URL = URL(string: "pushly://auth-callback") ?? URL(filePath: "/")

    public static func matches(_ url: URL) -> Bool {
        url.scheme == "pushly" && url.host == "auth-callback"
    }
}

public protocol ProfileServicing: Sendable {
    func fetchOwnProfile() async throws -> Profile
    func updateProfile(_ patch: ProfilePatch) async throws -> Profile
    func isUsernameAvailable(_ name: String) async throws -> Bool
}

/// `sync_alarms` RPC (roadmap P2-09). Payloads are the JSON of `AlarmSync.Change` / `AlarmSync.Response` (AlarmDomain),
/// passed through as data so Networking doesn't depend on the alarm domain.
public protocol AlarmSyncServicing: Sendable {
    func syncAlarms(_ changes: Data) async throws -> Data
}

/// Rep sessions + Wake tab (roadmap P4-03/P4-05/P4-06). Payloads are the JSON of shared/contracts (rep-log,
/// submit-rep-session response, wake-summary), passed through as data so Networking stays feature-agnostic.
/// Errors are `AppError`s; `retryable` tells the outbox whether to try again (doc 03 §5).
public protocol RepSessionServicing: Sendable {
    func submitRepSession(_ log: Data) async throws -> Data
    func wakeSummary() async throws -> Data
    /// Server time (epoch ms) from the `health` function — the anchor for rep timestamps (doc 06 §3).
    func serverTimeMs() async throws -> Int64
    /// `register_device(p)` with the device public key (register-device.request.schema.json); returns the device id.
    func registerDevice(_ request: Data) async throws -> String
}

/// Stats tab + achievements (roadmap P5-03/P5-05): JSON of shared/contracts/stats + achievements.
public protocol StatsServicing: Sendable {
    func stats(period: String) async throws -> Data
    func achievements() async throws -> Data
    /// `get_battle_stats()` (migration 0026): battle-stats.schema.json.
    func battleStats() async throws -> Data
}

/// Friends, feed, kudos and leaderboards (roadmap P6-02/P6-04): JSON of shared/contracts.
public protocol SocialServicing: Sendable {
    func listFriends() async throws -> Data
    func searchUsers(_ query: String) async throws -> Data
    func sendFriendRequest(_ userId: String) async throws -> String
    func respondFriendRequest(_ userId: String, accept: Bool) async throws -> String
    func removeFriend(_ userId: String) async throws -> String
    func blockUser(_ userId: String) async throws -> String
    func unblockUser(_ userId: String) async throws -> String
    func friendFeed() async throws -> Data
    func giveKudos(_ eventId: Int) async throws -> Int
    func leaderboard(board: String, scope: String, period: String) async throws -> Data
    /// `get_user_profile(user_id, username)` (migration 0023).
    func userProfile(id: String?, username: String?) async throws -> Data
    /// `set_profile_frame(frame)` (D-074): Pro frame or nil; returns my user card.
    func setProfileFrame(_ frame: String?) async throws -> Data
}

/// Clans (migration 0015): JSON of shared/contracts clan*.
public protocol ClanServicing: Sendable {
    func myClan() async throws -> Data
    func clan(_ id: String) async throws -> Data
    func searchClans(_ query: String) async throws -> Data
    /// `badge`: {shape, color, emblem} (D-074, shared/cosmetics/cosmetics.json).
    func createClan(name: String, tag: String, description: String, joinPolicy: String, badge: [String: String]) async throws -> Data
    /// `update_clan(patch)` — leaders / co-leaders: badge, description, join policy (nil = unchanged).
    func updateClan(badge: [String: String]?, description: String?, joinPolicy: String?) async throws -> Data
    func joinClan(_ id: String, message: String?) async throws -> String
    func respondClanRequest(_ userId: String, accept: Bool) async throws -> String
    func leaveClan() async throws -> String
    func kickMember(_ userId: String) async throws
    func setMemberRole(_ userId: String, role: String) async throws
    func transferLeadership(_ userId: String) async throws
    func clanMessages(before: Int?) async throws -> Data
    func sendClanMessage(_ body: String, kind: String) async throws
    /// `get_clan_war_history(clan_id, lim)` (migration 0021): clan-war-history.schema.json.
    func clanWarHistory(_ clanId: String?) async throws -> Data
    /// `get_war_chests()`: war-chests.schema.json.
    func warChests() async throws -> Data
    /// `clan_rally()` (migration 0027): clan-war.schema.json.
    func clanRally() async throws -> Data
    /// `open_chest(chest_id)`: {tier, xp, totalXp, level, xpIntoLevel, xpForNext}.
    func openChest(_ id: String) async throws -> Data
}

/// Account & data (migration 0016, doc 16 §4) and notification preferences (0011).
public protocol AccountServicing: Sendable {
    func exportMyData() async throws -> Data
    /// Needs a sign-in within the last 15 minutes (server error hint `reauth_required`).
    func deleteMyAccount() async throws
    /// `{"categories": {...}, "quietStart": "HH:MM", "quietEnd": "HH:MM"}` or empty object.
    func notificationPrefs() async throws -> Data
    func setNotificationPrefs(_ prefs: Data) async throws -> Data
    /// `get_privacy_settings()` (migration 0019): `{"ghostOptOut": Bool}`.
    func privacySettings() async throws -> Data
    /// `set_ghost_opt_out(opt_out)`: opting out also deletes recorded ghost runs.
    func setGhostOptOut(_ optOut: Bool) async throws
    /// `register_push_token(device_id, token)` (migration 0011): APNs / FCM token of this install's device row.
    func registerPushToken(deviceId: String, token: String) async throws
    /// `report(target, reason)` (migration 0016): target = {userId | battleId | messageId | clanId}.
    func report(target: [String: String], reason: String) async throws
}

/// Battles (migration 0014): JSON of shared/contracts battle*, matchmaking-status.
public protocol BattleServicing: Sendable {
    func battleInvites() async throws -> Data
    func createBattleInvite(toUser: String, mode: String, ranked: Bool) async throws -> Data
    func respondBattleInvite(_ id: String, accept: Bool) async throws -> Data
    func matchmakingJoin(mode: String) async throws -> Data
    func matchmakingStatus() async throws -> Data
    func matchmakingLeave() async throws
    func battle(_ id: String) async throws -> Data
    func battleReady(_ id: String) async throws -> Data
    func battlePushReps(_ id: String, reps: Data) async throws
    func battleFinish(_ id: String) async throws -> Data
    func battleForfeit(_ id: String) async throws -> Data
    func battleHistory() async throws -> Data
    /// `start_ghost_battle(mode)` (migration 0018).
    func startGhostBattle(mode: String) async throws -> Data
    /// `start_bot_battle(mode, level)` (migration 0024): a labelled practice bot; level nil = fits the player.
    func startBotBattle(mode: String, level: String?) async throws -> Data
    /// Edge Function `battle-token` (doc 07 §4.1): LiveKit {url, token, room, expiresInS} for my battle.
    func battleVideoToken(_ battleId: String) async throws -> Data
    /// `get_season_history()` (migration 0022): season-history.schema.json.
    func seasonHistory() async throws -> Data
}

public protocol RemoteConfigServicing: Sendable {
    func fetch() async throws -> RemoteConfig
}

/// Backend connection settings, read from Info.plist keys `SupabaseURL` / `SupabaseAnonKey` (set via xcconfig).
public struct BackendConfig: Sendable, Equatable {
    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Nil when the build has no backend configured (e.g. CI or a fresh checkout without Secrets.xcconfig):
    /// the app then runs in offline/guest mode and says so on the sign-in screen.
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> BackendConfig? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !key.isEmpty, !rawURL.contains("$("),
              let url = URL(string: rawURL), url.scheme?.hasPrefix("http") == true, url.host != nil
        else { return nil }
        return BackendConfig(url: url, anonKey: key)
    }
}
