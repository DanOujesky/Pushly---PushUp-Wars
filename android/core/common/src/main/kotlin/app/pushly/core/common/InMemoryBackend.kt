package app.pushly.core.common

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

/**
 * In-memory backend for previews and unit tests. Mirrors the server rules the UI depends on
 * (username uniqueness, age gate, onboarding completion). Same behaviour as iOS `InMemoryBackend`.
 */
class InMemoryBackend(
    signedInAs: Profile? = null,
    var currentYear: Int = java.time.Year.now().value,
) : AuthService, ProfileService, RemoteConfigService {
    private val mutex = Mutex()
    private val userId = MutableStateFlow(signedInAs?.id)
    var profile: Profile? = signedInAs
        private set
    val sentCodes = mutableListOf<String>()
    var takenUsernames = mutableSetOf("taken", "anafit")
    var config = RemoteConfig()
    var nextError: AppError? = null
    var validCode = "123456"

    private fun failIfNeeded() {
        nextError?.let {
            nextError = null
            throw it
        }
    }

    override suspend fun currentUserId(): String? = userId.value

    override fun authStateChanges(): Flow<String?> = userId.asStateFlow()

    override suspend fun sendEmailCode(email: String) {
        mutex.withLock {
            failIfNeeded()
            sentCodes.add(email)
        }
    }

    override suspend fun verifyEmailCode(email: String, code: String): String = mutex.withLock {
        failIfNeeded()
        if (code != validCode) throw AppError(AppErrorCode.Unauthenticated, "invalid code")
        signIn()
    }

    /** Test helper: sign in directly (like a completed OAuth flow). */
    suspend fun signInDirectly(): String = mutex.withLock { signIn() }

    override suspend fun signInWithGoogle(idToken: String): String = mutex.withLock {
        failIfNeeded()
        signIn()
    }

    private fun signIn(): String {
        val id = profile?.id ?: UUID.randomUUID().toString()
        if (profile == null) {
            profile = Profile(id = id, username = "u_" + id.replace("-", "").takeLast(12), onboardingCompleted = false)
        }
        userId.value = id
        return id
    }

    override suspend fun handleAuthCallback(url: String): String = mutex.withLock {
        failIfNeeded()
        if (!AuthCallback.matches(url)) throw AppError(AppErrorCode.ValidationFailed, "not an auth callback")
        signIn()
    }

    override suspend fun signOut() {
        mutex.withLock {
            failIfNeeded()
            userId.value = null
        }
    }

    override suspend fun fetchOwnProfile(): Profile = mutex.withLock {
        failIfNeeded()
        val p = profile
        if (userId.value == null || p == null) throw AppError(AppErrorCode.Unauthenticated, "signed out")
        p
    }

    override suspend fun updateProfile(patch: ProfilePatch): Profile = mutex.withLock {
        failIfNeeded()
        val base = profile
        if (userId.value == null || base == null) throw AppError(AppErrorCode.Unauthenticated, "signed out")
        var p: Profile = base
        patch.username?.let { name ->
            AccountRules.usernameError(name)?.let { throw AppError(AppErrorCode.ValidationFailed, it.wire) }
            if (name.lowercase() in takenUsernames) throw AppError(AppErrorCode.Conflict, "taken")
            p = p.copy(username = name)
        }
        patch.birthYear?.let { year ->
            if (AccountRules.birthYearError(year, currentYear) != null) {
                throw AppError(AppErrorCode.ValidationFailed, "minimum age is 16")
            }
            p = p.copy(birthYear = year)
        }
        patch.avatarPreset?.let { p = p.copy(avatarPreset = it) }
        patch.country?.let { p = p.copy(country = it.uppercase()) }
        patch.timezone?.let { p = p.copy(timezone = it) }
        patch.profileVisibility?.let { p = p.copy(profileVisibility = it) }
        patch.leaderboardVisible?.let { p = p.copy(leaderboardVisible = it) }
        val completed = p.onboardingCompleted || (p.birthYear != null && AccountRules.usernameError(p.username) == null)
        p = p.copy(onboardingCompleted = completed)
        profile = p
        p
    }

    override suspend fun isUsernameAvailable(name: String): Boolean = mutex.withLock {
        failIfNeeded()
        AccountRules.usernameError(name) == null && name.lowercase() !in takenUsernames
    }

    override suspend fun fetch(): RemoteConfig = mutex.withLock {
        failIfNeeded()
        config
    }
}
