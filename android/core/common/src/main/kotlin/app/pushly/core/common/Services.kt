package app.pushly.core.common

import kotlinx.coroutines.flow.Flow

/** Authentication (doc 02 PS-02). Implementations: SupabaseBackend (real), InMemoryBackend (tests, previews). */
interface AuthService {
    suspend fun currentUserId(): String?

    /** Emits the user id whenever auth state changes (null = signed out). */
    fun authStateChanges(): Flow<String?>
    suspend fun sendEmailCode(email: String)
    suspend fun verifyEmailCode(email: String, code: String): String
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
}
