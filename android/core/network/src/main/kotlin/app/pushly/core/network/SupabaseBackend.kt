package app.pushly.core.network

import app.pushly.core.common.AppConfigRow
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.AuthCallback
import app.pushly.core.common.AuthService
import app.pushly.core.common.Profile
import app.pushly.core.common.ProfilePatch
import app.pushly.core.common.ProfileService
import app.pushly.core.common.RemoteConfig
import app.pushly.core.common.RemoteConfigService
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.transform
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import java.io.IOException

/** Backend connection settings (from BuildConfig, filled from local.properties / CI secrets). */
data class BackendConfig(val url: String, val anonKey: String) {
    companion object {
        /** Null when the build has no backend configured — the app then runs guest-only. */
        fun fromBuild(url: String, anonKey: String): BackendConfig? =
            if (url.startsWith("http") && anonKey.isNotBlank()) BackendConfig(url, anonKey) else null
    }
}

class SupabaseBackend(config: BackendConfig) : AuthService, ProfileService, RemoteConfigService {
    private val client = createSupabaseClient(supabaseUrl = config.url, supabaseKey = config.anonKey) {
        install(Auth) {
            flowType = FlowType.PKCE
            scheme = "pushly"
            host = "auth-callback"
        }
        install(Postgrest)
    }
    private val patchJson = Json { explicitNulls = false }

    // Auth

    override suspend fun currentUserId(): String? {
        client.auth.awaitInitialization()
        return client.auth.currentUserOrNull()?.id
    }

    override fun authStateChanges(): Flow<String?> = client.auth.sessionStatus
        .transform { status ->
            when (status) {
                is SessionStatus.Authenticated -> emit(status.session.user?.id)
                is SessionStatus.NotAuthenticated -> emit(null)
                else -> Unit // initializing / refresh failure: no change
            }
        }
        .distinctUntilChanged()

    override suspend fun sendEmailCode(email: String) = mapErrors {
        client.auth.signInWith(OTP, redirectUrl = AuthCallback.URL) {
            this.email = email
            createUser = true
        }
    }

    override suspend fun verifyEmailCode(email: String, code: String): String = mapErrors {
        client.auth.verifyEmailOtp(type = OtpType.Email.EMAIL, email = email, token = code)
        client.auth.currentUserOrNull()?.id ?: throw AppError(AppErrorCode.Unauthenticated, "No session after verification")
    }

    override suspend fun signOut() = mapErrors { client.auth.signOut() }

    override suspend fun handleAuthCallback(url: String): String = mapErrors {
        val code = AuthCallback.code(url) ?: throw AppError(AppErrorCode.ValidationFailed, "callback without code")
        client.auth.exchangeCodeForSession(code)
        client.auth.currentUserOrNull()?.id ?: throw AppError(AppErrorCode.Unauthenticated, "No session after callback")
    }

    // Profile

    override suspend fun fetchOwnProfile(): Profile = mapErrors {
        val uid = client.auth.currentUserOrNull()?.id ?: throw AppError(AppErrorCode.Unauthenticated, "signed out")
        client.from("profiles").select { filter { eq("id", uid) } }.decodeSingle<Profile>()
    }

    override suspend fun updateProfile(patch: ProfilePatch): Profile = mapErrors {
        val params = buildJsonObject { put("patch", patchJson.encodeToJsonElement(patch)) }
        client.postgrest.rpc("update_profile", params).decodeAs<Profile>()
    }

    override suspend fun isUsernameAvailable(name: String): Boolean = mapErrors {
        client.postgrest.rpc("username_available", buildJsonObject { put("name", name) }).decodeAs<Boolean>()
    }

    // Remote config

    override suspend fun fetch(): RemoteConfig = mapErrors {
        val rows = client.from("app_config").select().decodeList<AppConfigRow>()
        RemoteConfig.fromRows(rows, "android")
    }

    private suspend fun <T> mapErrors(block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: AppError) {
        throw e
    } catch (e: Exception) {
        throw BackendErrorMapper.map(e)
    }
}

/** Maps SDK / transport errors to AppError (doc 12). Pure — unit tested. Same table as iOS. */
object BackendErrorMapper {
    private val CODES = listOf("23505", "22023", "P0001", "28000", "42501", "P0002")

    fun map(error: Throwable): AppError {
        if (error is IOException || error.cause is IOException) return AppError(AppErrorCode.Network, error.message ?: "network")
        val text = error.toString() + " " + (error.message ?: "")
        return map(CODES.firstOrNull { text.contains(it) }, text)
    }

    fun map(postgresCode: String?, message: String): AppError = when (postgresCode) {
        "23505" -> AppError(AppErrorCode.Conflict, "taken")
        "22023", "P0001" -> AppError(AppErrorCode.ValidationFailed, message)
        "28000", "42501" -> AppError(AppErrorCode.Forbidden, message)
        "P0002" -> AppError(AppErrorCode.NotFound, message)
        else -> AppError(AppErrorCode.Unknown, message)
    }
}
