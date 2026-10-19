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
}

interface ProfileService {
    suspend fun fetchOwnProfile(): Profile
    suspend fun updateProfile(patch: ProfilePatch): Profile
    suspend fun isUsernameAvailable(name: String): Boolean
}

interface RemoteConfigService {
    suspend fun fetch(): RemoteConfig
}
