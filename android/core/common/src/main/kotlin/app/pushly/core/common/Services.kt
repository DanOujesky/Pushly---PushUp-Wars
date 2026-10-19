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

interface RemoteConfigService {
    suspend fun fetch(): RemoteConfig
}
