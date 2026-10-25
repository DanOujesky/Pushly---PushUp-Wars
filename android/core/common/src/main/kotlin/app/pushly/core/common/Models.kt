package app.pushly.core.common

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Raw values match the Postgres enum `visibility_t`. */
@Serializable
enum class ProfileVisibility {
    @SerialName("public") Public,
    @SerialName("friends") Friends,
    @SerialName("private") Private,
}

/** The signed-in user's own profile row (`public.profiles`). Fixture: shared/contracts/fixtures/profile.json */
@Serializable
data class Profile(
    val id: String,
    val username: String,
    @SerialName("onboarding_completed") val onboardingCompleted: Boolean,
    @SerialName("avatar_preset") val avatarPreset: String? = null,
    @SerialName("avatar_path") val avatarPath: String? = null,
    val country: String? = null,
    @SerialName("birth_year") val birthYear: Int? = null,
    val timezone: String = "UTC",
    @SerialName("profile_visibility") val profileVisibility: ProfileVisibility = ProfileVisibility.Public,
    @SerialName("leaderboard_visible") val leaderboardVisible: Boolean = true,
    val trophies: Int = 0,
    val xp: Int = 0,
    val level: Int = 1,
    @SerialName("is_pro") val isPro: Boolean = false,
    /** Pro profile frame (D-074); shown only while Pro. */
    val frame: String? = null,
)

/** Fields accepted by RPC `update_profile(patch)`. Null fields are not sent (encode with `explicitNulls = false`). */
@Serializable
data class ProfilePatch(
    val username: String? = null,
    @SerialName("avatar_preset") val avatarPreset: String? = null,
    val country: String? = null,
    @SerialName("birth_year") val birthYear: Int? = null,
    val timezone: String? = null,
    @SerialName("profile_visibility") val profileVisibility: ProfileVisibility? = null,
    @SerialName("leaderboard_visible") val leaderboardVisible: Boolean? = null,
)

@Serializable
data class AppConfigRow(val key: String, val value: JsonElement)

/** Remote config (`public.app_config`, doc 03 §7) reduced to what the app uses. */
data class RemoteConfig(
    val minSupportedVersion: String = "0.0.0",
    val killSwitches: Map<String, Boolean> = emptyMap(),
) {
    companion object {
        fun fromRows(rows: List<AppConfigRow>, platform: String): RemoteConfig {
            var config = RemoteConfig()
            for (row in rows) {
                val obj = row.value as? JsonObject ?: continue
                when (row.key) {
                    "min_supported_version" -> obj[platform]?.jsonPrimitive?.contentOrNull?.let {
                        config = config.copy(minSupportedVersion = it)
                    }
                    "kill_switches" -> config = config.copy(
                        killSwitches = obj.mapNotNull { (k, v) -> v.jsonPrimitive.booleanOrNull?.let { k to it } }.toMap(),
                    )
                }
            }
            return config
        }
    }
}
