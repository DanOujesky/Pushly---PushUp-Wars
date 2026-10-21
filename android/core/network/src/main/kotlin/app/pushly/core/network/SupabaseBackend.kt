package app.pushly.core.network

import app.pushly.core.common.AccountService
import app.pushly.core.common.AlarmSyncService
import app.pushly.core.common.AppConfigRow
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.AuthCallback
import app.pushly.core.common.AuthService
import app.pushly.core.common.BattleService
import app.pushly.core.common.ClanService
import app.pushly.core.common.Profile
import app.pushly.core.common.ProfilePatch
import app.pushly.core.common.ProfileService
import app.pushly.core.common.RemoteConfig
import app.pushly.core.common.RemoteConfigService
import app.pushly.core.common.RepSessionService
import app.pushly.core.common.SocialService
import app.pushly.core.common.StatsService
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.functions.functions
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
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.io.IOException

/** Backend connection settings (from BuildConfig, filled from local.properties / CI secrets). */
data class BackendConfig(val url: String, val anonKey: String) {
    companion object {
        /** Null when the build has no backend configured — the app then runs guest-only. */
        fun fromBuild(url: String, anonKey: String): BackendConfig? =
            if (url.startsWith("http") && anonKey.isNotBlank()) BackendConfig(url, anonKey) else null
    }
}

class SupabaseBackend(config: BackendConfig) :
    AuthService,
    ProfileService,
    RemoteConfigService,
    AlarmSyncService,
    RepSessionService,
    StatsService,
    SocialService,
    ClanService,
    AccountService,
    BattleService {
    private val client = createSupabaseClient(supabaseUrl = config.url, supabaseKey = config.anonKey) {
        install(Auth) {
            flowType = FlowType.PKCE
            scheme = "pushly"
            host = "auth-callback"
        }
        install(Postgrest)
        install(Functions)
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

    override suspend fun syncAlarms(changesJson: String): String = mapErrors {
        val changes = Json.parseToJsonElement(changesJson)
        client.postgrest.rpc("sync_alarms", buildJsonObject { put("changes", changes) }).data
    }

    // Rep sessions (P4-03/P4-05)

    override suspend fun submitRepSession(logJson: String): String = mapErrors {
        client.functions.invoke(function = "submit-rep-session", body = Json.parseToJsonElement(logJson)).bodyAsText()
    }

    override suspend fun wakeSummary(): String = mapErrors {
        client.postgrest.rpc("get_wake_summary").data
    }

    // Social (migration 0011). Text results come back as JSON strings ("pending") — unquoted here.
    private suspend fun rpcText(name: String, params: kotlinx.serialization.json.JsonObject): String =
        client.postgrest.rpc(name, params).data.trim().trim('"')

    override suspend fun listFriends(): String = mapErrors { client.postgrest.rpc("list_friends").data }

    override suspend fun searchUsers(query: String): String = mapErrors {
        client.postgrest.rpc("search_users", buildJsonObject { put("q", query) }).data
    }

    override suspend fun sendFriendRequest(userId: String): String = mapErrors {
        rpcText("send_friend_request", buildJsonObject { put("target", userId) })
    }

    override suspend fun respondFriendRequest(userId: String, accept: Boolean): String = mapErrors {
        rpcText("respond_friend_request", buildJsonObject {
            put("requester", userId)
            put("accept", accept)
        })
    }

    override suspend fun removeFriend(userId: String): String = mapErrors {
        rpcText("remove_friend", buildJsonObject { put("target", userId) })
    }

    override suspend fun blockUser(userId: String): String = mapErrors {
        rpcText("block_user", buildJsonObject { put("target", userId) })
    }

    override suspend fun unblockUser(userId: String): String = mapErrors {
        rpcText("unblock_user", buildJsonObject { put("target", userId) })
    }

    override suspend fun friendFeed(): String = mapErrors { client.postgrest.rpc("get_friend_feed").data }

    override suspend fun giveKudos(eventId: Long): Int = mapErrors {
        rpcText("give_kudos", buildJsonObject { put("event_id", eventId) }).toInt()
    }

    override suspend fun leaderboard(board: String, scope: String, period: String): String = mapErrors {
        client.postgrest.rpc("get_leaderboard", buildJsonObject {
            put("board", board)
            put("scope", scope)
            put("period", period)
        }).data
    }

    // Battles (migration 0014)
    override suspend fun battleInvites(): String = mapErrors { client.postgrest.rpc("list_battle_invites").data }

    override suspend fun createBattleInvite(toUser: String, mode: String, ranked: Boolean): String = mapErrors {
        client.postgrest.rpc("create_battle_invite", buildJsonObject {
            put("to_user", toUser)
            put("mode", mode)
            put("ranked", ranked)
        }).data
    }

    override suspend fun respondBattleInvite(id: String, accept: Boolean): String = mapErrors {
        client.postgrest.rpc("respond_battle_invite", buildJsonObject {
            put("invite_id", id)
            put("accept", accept)
        }).data
    }

    override suspend fun matchmakingJoin(mode: String): String = mapErrors {
        client.postgrest.rpc("matchmaking_join", buildJsonObject { put("mode", mode) }).data
    }

    override suspend fun matchmakingStatus(): String = mapErrors { client.postgrest.rpc("matchmaking_status").data }

    override suspend fun matchmakingLeave() {
        mapErrors { client.postgrest.rpc("matchmaking_leave") }
    }

    private suspend fun battleRpc(name: String, id: String): String =
        client.postgrest.rpc(name, buildJsonObject { put("battle_id", id) }).data

    override suspend fun battle(id: String): String = mapErrors { battleRpc("get_battle", id) }

    override suspend fun battleReady(id: String): String = mapErrors { battleRpc("battle_ready", id) }

    override suspend fun battlePushReps(id: String, repsJson: String) {
        mapErrors {
            client.postgrest.rpc("battle_push_rep", buildJsonObject {
                put("battle_id", id)
                put("reps", Json.parseToJsonElement(repsJson))
            })
        }
    }

    override suspend fun battleFinish(id: String): String = mapErrors { battleRpc("battle_finish", id) }

    override suspend fun battleForfeit(id: String): String = mapErrors { battleRpc("battle_forfeit", id) }

    override suspend fun battleHistory(): String = mapErrors { client.postgrest.rpc("battle_history").data }

    override suspend fun startGhostBattle(mode: String): String = mapErrors {
        client.postgrest.rpc("start_ghost_battle", buildJsonObject { put("mode", mode) }).data
    }

    // Account (migration 0016)
    override suspend fun exportMyData(): String = mapErrors { client.postgrest.rpc("export_my_data").data }

    override suspend fun deleteMyAccount() {
        mapErrors { client.postgrest.rpc("delete_my_account") }
        runCatching { client.auth.signOut() }
    }

    override suspend fun notificationPrefs(): String = mapErrors {
        val rows = Json.parseToJsonElement(client.from("notification_prefs").select().data)
        (rows as? kotlinx.serialization.json.JsonArray)?.firstOrNull()?.jsonObject?.get("prefs")?.toString() ?: "{}"
    }

    override suspend fun setNotificationPrefs(prefsJson: String): String = mapErrors {
        client.postgrest.rpc("set_notification_prefs", buildJsonObject { put("p", Json.parseToJsonElement(prefsJson)) }).data
    }

    override suspend fun privacySettings(): String = mapErrors { client.postgrest.rpc("get_privacy_settings").data }

    override suspend fun registerPushToken(deviceId: String, token: String) {
        mapErrors {
            client.postgrest.rpc("register_push_token", buildJsonObject {
                put("device_id", deviceId)
                put("token", token)
            })
        }
    }

    override suspend fun setGhostOptOut(optOut: Boolean) {
        mapErrors { client.postgrest.rpc("set_ghost_opt_out", buildJsonObject { put("opt_out", optOut) }) }
    }

    // Clans (migration 0015)
    override suspend fun myClan(): String = mapErrors { client.postgrest.rpc("get_clan", buildJsonObject { }).data }

    override suspend fun searchClans(query: String): String = mapErrors {
        client.postgrest.rpc("search_clans", buildJsonObject { put("q", query) }).data
    }

    override suspend fun createClan(name: String, tag: String, description: String, joinPolicy: String): String = mapErrors {
        client.postgrest.rpc("create_clan", buildJsonObject {
            put("name", name)
            put("tag", tag)
            put("description", description)
            put("join_policy", joinPolicy)
        }).data
    }

    override suspend fun joinClan(clanId: String, message: String?): String = mapErrors {
        rpcText("join_clan", buildJsonObject {
            put("clan_id", clanId)
            put("message", message)
        })
    }

    override suspend fun respondClanRequest(userId: String, accept: Boolean): String = mapErrors {
        rpcText("respond_clan_request", buildJsonObject {
            put("user_id", userId)
            put("accept", accept)
        })
    }

    override suspend fun leaveClan(): String = mapErrors { client.postgrest.rpc("leave_clan").data.trim().trim('"') }

    override suspend fun kickMember(userId: String) {
        mapErrors { client.postgrest.rpc("kick_member", buildJsonObject { put("user_id", userId) }) }
    }

    override suspend fun setMemberRole(userId: String, role: String) {
        mapErrors {
            client.postgrest.rpc("set_member_role", buildJsonObject {
                put("user_id", userId)
                put("role", role)
            })
        }
    }

    override suspend fun transferLeadership(userId: String) {
        mapErrors { client.postgrest.rpc("transfer_leadership", buildJsonObject { put("user_id", userId) }) }
    }

    override suspend fun clanMessages(beforeId: Long?): String = mapErrors {
        client.postgrest.rpc("get_clan_messages", buildJsonObject {
            if (beforeId != null) put("before_id", beforeId)
            put("lim", 100)
        }).data
    }

    override suspend fun sendClanMessage(body: String, kind: String) {
        mapErrors {
            client.postgrest.rpc("send_clan_message", buildJsonObject {
                put("body", body)
                put("kind", kind)
            })
        }
    }

    override suspend fun clanWarHistory(clanId: String?): String = mapErrors {
        client.postgrest.rpc("get_clan_war_history", buildJsonObject {
            put("clan_id", clanId)
            put("lim", 20)
        }).data
    }

    override suspend fun warChests(): String = mapErrors { client.postgrest.rpc("get_war_chests").data }

    override suspend fun openChest(id: String): String = mapErrors {
        client.postgrest.rpc("open_chest", buildJsonObject { put("chest_id", id) }).data
    }

    override suspend fun stats(period: String): String = mapErrors {
        client.postgrest.rpc("get_stats", buildJsonObject { put("period", period) }).data
    }

    override suspend fun achievements(): String = mapErrors {
        client.postgrest.rpc("get_achievements").data
    }

    override suspend fun registerDevice(requestJson: String): String = mapErrors {
        val p = Json.parseToJsonElement(requestJson)
        client.postgrest.rpc("register_device", buildJsonObject { put("p", p) }).data.trim().trim('"')
    }

    override suspend fun serverTimeMs(): Long = mapErrors {
        Json.parseToJsonElement(client.functions.invoke(function = "health").bodyAsText())
            .jsonObject["serverMs"]?.jsonPrimitive?.long ?: throw AppError(AppErrorCode.Internal, "health: no serverMs")
    }

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
        if (error is RestException) return map(httpStatus = error.statusCode, body = error.message ?: "")
        val text = error.toString() + " " + (error.message ?: "")
        return map(CODES.firstOrNull { text.contains(it) }, text)
    }

    /** Edge Function errors (doc 12 format) — the code in the body wins, else the HTTP status. */
    fun map(httpStatus: Int, body: String): AppError {
        AppErrorCode.entries.firstOrNull { body.contains("\"${it.wire}\"") }?.let { return AppError(it, body) }
        val code = when (httpStatus) {
            401 -> AppErrorCode.Unauthenticated
            403 -> AppErrorCode.Forbidden
            404 -> AppErrorCode.NotFound
            409 -> AppErrorCode.Conflict
            400, 422 -> AppErrorCode.ValidationFailed
            426 -> AppErrorCode.UpgradeRequired
            429 -> AppErrorCode.RateLimited
            else -> if (httpStatus >= 500) AppErrorCode.Internal else AppErrorCode.Unknown
        }
        return AppError(code, "HTTP $httpStatus")
    }

    fun map(postgresCode: String?, message: String): AppError = when (postgresCode) {
        "23505" -> AppError(AppErrorCode.Conflict, "taken")
        "22023", "P0001" -> AppError(AppErrorCode.ValidationFailed, message)
        "28000", "42501" -> AppError(AppErrorCode.Forbidden, message)
        "P0002" -> AppError(AppErrorCode.NotFound, message)
        else -> AppError(AppErrorCode.Unknown, message)
    }
}
