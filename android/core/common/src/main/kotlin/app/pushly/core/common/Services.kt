package app.pushly.core.common

import kotlinx.coroutines.flow.Flow

/** Authentication (doc 02 PS-02). Implementations: SupabaseBackend (real), InMemoryBackend (tests, previews). */
interface AuthService {
    suspend fun currentUserId(): String?

    /** Emits the user id whenever auth state changes (null = signed out). */
    fun authStateChanges(): Flow<String?>
    suspend fun sendEmailCode(email: String)
    suspend fun verifyEmailCode(email: String, code: String): String

    /** Google ID token from Credential Manager (Supabase provider "google", D-061). Returns the user id. */
    suspend fun signInWithGoogle(idToken: String): String

    /**
     * Google sign-in in the browser (Supabase OAuth + PKCE, D-078) — the fallback when the native sheet is unavailable.
     * Opens the browser; the session arrives later through `pushly://auth-callback` ([handleAuthCallback]).
     */
    suspend fun startGoogleBrowserSignIn(): Unit = throw AppError(AppErrorCode.Unknown, "browser sign-in not available")
    suspend fun signOut()

    /** Completes a sign-in from an email link (`pushly://auth-callback?code=...`). Returns the user id. */
    suspend fun handleAuthCallback(url: String): String
}

object AuthCallback {
    /** Redirect target of sign-in emails; must be in Supabase `additional_redirect_urls` (supabase/config.toml). */
    const val URL = "pushly://auth-callback"

    fun matches(url: String?): Boolean = url != null && (url == URL || url.startsWith("$URL?") || url.startsWith("$URL#"))

    /** PKCE `code` query parameter of a callback URL, if present. */
    fun code(url: String): String? =
        url.substringAfter('?', "").substringBefore('#').split('&')
            .map { it.split('=', limit = 2) }
            .firstOrNull { it.size == 2 && it[0] == "code" }
            ?.get(1)
            ?.let { java.net.URLDecoder.decode(it, Charsets.UTF_8) }
}

interface ProfileService {
    suspend fun fetchOwnProfile(): Profile
    suspend fun updateProfile(patch: ProfilePatch): Profile
    suspend fun isUsernameAvailable(name: String): Boolean
}

/**
 * `sync_alarms` RPC (roadmap P2-09). Payloads are the JSON of `AlarmSync.Change` / `AlarmSync.Response` (:core:alarm),
 * passed through as text so the network layer doesn't depend on the alarm domain.
 */
interface AlarmSyncService {
    suspend fun syncAlarms(changesJson: String): String
}

/**
 * Rep sessions + Wake tab (roadmap P4-03/P4-05/P4-06). Payloads are the JSON of shared/contracts (rep-log,
 * submit-rep-session response, wake-summary) as text. Errors are [AppError]s; `retryable` drives the outbox.
 */
interface RepSessionService {
    suspend fun submitRepSession(logJson: String): String
    suspend fun wakeSummary(): String

    /** Server time (epoch ms) from the `health` function — the anchor for rep timestamps (doc 06 §3). */
    suspend fun serverTimeMs(): Long

    /** `register_device(p)` with the device public key (register-device.request.schema.json); returns the device id. */
    suspend fun registerDevice(requestJson: String): String
}

interface RemoteConfigService {
    suspend fun fetch(): RemoteConfig
}

/** Stats tab + achievements (roadmap P5-03/P5-05): JSON of shared/contracts/stats + achievements. */
interface StatsService {
    suspend fun stats(period: String): String
    suspend fun achievements(): String

    /** `get_battle_stats()` (migration 0026): battle-stats.schema.json. */
    suspend fun battleStats(): String = throw UnsupportedOperationException("battle stats")
}

/** Friends, feed, kudos and leaderboards (roadmap P6-02/P6-04): JSON of shared/contracts. */
interface SocialService {
    suspend fun listFriends(): String
    suspend fun searchUsers(query: String): String
    suspend fun sendFriendRequest(userId: String): String
    suspend fun respondFriendRequest(userId: String, accept: Boolean): String
    suspend fun removeFriend(userId: String): String
    suspend fun blockUser(userId: String): String
    suspend fun unblockUser(userId: String): String
    suspend fun friendFeed(): String
    suspend fun giveKudos(eventId: Long): Int
    suspend fun leaderboard(board: String, scope: String, period: String): String
    /** `get_user_profile(user_id, username)` (migration 0023): user-profile.schema.json, JSON null when not found. */
    suspend fun userProfile(userId: String?, username: String?): String

    /** `set_profile_frame(frame)` (D-074): a Pro frame or null; returns my user card. */
    suspend fun setProfileFrame(frame: String?): String = throw UnsupportedOperationException("set_profile_frame")
}

/** Clans (migration 0015): JSON of shared/contracts clan*. */
interface ClanService {
    suspend fun myClan(): String
    suspend fun searchClans(query: String): String
    suspend fun createClan(name: String, tag: String, description: String, joinPolicy: String): String

    /** With a badge {shape, color, emblem} (D-074, shared/cosmetics/cosmetics.json). */
    suspend fun createClan(name: String, tag: String, description: String, joinPolicy: String, badge: Map<String, String>): String =
        createClan(name, tag, description, joinPolicy)

    /** `update_clan(patch)` — leaders / co-leaders: badge, description, join policy (null = unchanged). */
    suspend fun updateClan(badge: Map<String, String>?, description: String?, joinPolicy: String?): String =
        throw UnsupportedOperationException("update_clan")
    suspend fun joinClan(clanId: String, message: String?): String
    suspend fun respondClanRequest(userId: String, accept: Boolean): String
    suspend fun leaveClan(): String
    suspend fun kickMember(userId: String)
    suspend fun setMemberRole(userId: String, role: String)
    suspend fun transferLeadership(userId: String)
    suspend fun clanMessages(beforeId: Long?): String
    suspend fun sendClanMessage(body: String, kind: String)
    /** `get_clan_war_history(clan_id, lim)` (migration 0021): clan-war-history.schema.json. */
    suspend fun clanWarHistory(clanId: String?): String
    /** `get_war_chests()`: war-chests.schema.json. */
    suspend fun warChests(): String
    /** `open_chest(chest_id)`: {tier, xp, totalXp, level, xpIntoLevel, xpForNext}. */
    suspend fun openChest(id: String): String

    /** `clan_rally()` (migration 0027): push + chat to the whole clan; returns the war card. */
    suspend fun clanRally(): String = throw UnsupportedOperationException("rally")

    /** `get_clan_leaderboard('rating')` (clan-leaderboard.schema.json). */
    suspend fun clanLeaderboard(): String = throw UnsupportedOperationException("clan leaderboard")
}

/** Account & data (migration 0016, doc 16 §4) and notification preferences (0011). */
interface AccountService {
    suspend fun exportMyData(): String
    /** Needs a sign-in within the last 15 minutes (server hint `reauth_required`). */
    suspend fun deleteMyAccount()
    /** `{"categories": {...}, "quietStart": "HH:MM", "quietEnd": "HH:MM"}` or `{}`. */
    suspend fun notificationPrefs(): String
    suspend fun setNotificationPrefs(prefsJson: String): String
    /** `get_privacy_settings()` (migration 0019): `{"ghostOptOut": Boolean}`. */
    suspend fun privacySettings(): String
    /** `set_ghost_opt_out(opt_out)`: opting out also deletes recorded ghost runs. */
    suspend fun setGhostOptOut(optOut: Boolean)
    /** `register_push_token(device_id, token)` (migration 0011): FCM / APNs token of this install's device row. */
    suspend fun registerPushToken(deviceId: String, token: String)
    /** `report(target, reason)` (migration 0016): target = {userId | battleId | messageId | clanId}. */
    suspend fun report(target: Map<String, String>, reason: String)
}

/** Battles (migration 0014): JSON of shared/contracts battle*, matchmaking-status. */
interface BattleService {
    suspend fun battleInvites(): String
    suspend fun createBattleInvite(toUser: String, mode: String, ranked: Boolean): String
    suspend fun respondBattleInvite(id: String, accept: Boolean): String
    suspend fun matchmakingJoin(mode: String): String
    suspend fun matchmakingStatus(): String
    suspend fun matchmakingLeave()
    suspend fun battle(id: String): String
    suspend fun battleReady(id: String): String
    suspend fun battlePushReps(id: String, repsJson: String)
    suspend fun battleFinish(id: String): String
    suspend fun battleForfeit(id: String): String
    suspend fun battleHistory(): String

    /** `start_ghost_battle(mode)` (migration 0018): never ranked, 3 a day for free users. */
    suspend fun startGhostBattle(mode: String): String

    /** `start_bot_battle(mode, level)` (migration 0024): a labelled practice bot; level null = fits the player. */
    suspend fun startBotBattle(mode: String, level: String?): String = throw UnsupportedOperationException("bots")

    /** Edge Function `battle-token` (doc 07 §4.1): LiveKit {url, token, room, expiresInS} for my battle. */
    suspend fun battleVideoToken(battleId: String): String = throw UnsupportedOperationException("video")

    /** `get_season_history()` (migration 0022): season-history.schema.json. */
    suspend fun seasonHistory(): String

    /** `matchmaking_bot()` (migration 0031, D-075): nobody found after 10 s → a ranked Arena Bot battle. */
    suspend fun matchmakingBot(): String = throw UnsupportedOperationException("arena bot")
}
