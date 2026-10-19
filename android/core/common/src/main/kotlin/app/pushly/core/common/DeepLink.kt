package app.pushly.core.common

import java.net.URI
import java.util.UUID

/** Deep links (doc 15 §3). Same rules as iOS `DeepLink` (ios/Packages/Core). */
sealed interface DeepLink {
    data object Wake : DeepLink
    data class Alarm(val id: UUID) : DeepLink
    data class BattleInvite(val code: String) : DeepLink
    data class Battle(val id: UUID) : DeepLink
    data class Clan(val id: UUID) : DeepLink
    data class ClanWar(val id: UUID) : DeepLink
    data class User(val username: String) : DeepLink
    data class Leaderboard(val board: String) : DeepLink
    data object AlarmHealth : DeepLink
    data object Pro : DeepLink

    companion object {
        const val WEB_HOST = "pushly.app"
        const val SCHEME = "pushly"

        private val CODE = Regex("^[A-Za-z0-9]{4,12}$")
        private val USERNAME = Regex("^[A-Za-z0-9_.]{3,20}$")
        private val BOARDS = setOf("wake", "streak", "battles", "total", "clans")

        fun parse(url: String): DeepLink? {
            val uri = runCatching { URI(url) }.getOrNull() ?: return null
            val segments: List<String> = when {
                uri.scheme == SCHEME -> listOfNotNull(uri.host) + pathSegments(uri)
                uri.scheme == "https" && uri.host == WEB_HOST -> pathSegments(uri)
                else -> return null
            }.filter { it.isNotEmpty() }
            return parse(segments)
        }

        private fun pathSegments(uri: URI): List<String> = (uri.path ?: "").split('/')

        private fun parse(p: List<String>): DeepLink? = when (p.size) {
            1 -> when (p[0]) {
                "wake" -> Wake
                "pro" -> Pro
                else -> null
            }
            2 -> when (p[0]) {
                "alarm" -> uuid(p[1])?.let(::Alarm)
                "battle" -> uuid(p[1])?.let(::Battle)
                "b" -> p[1].takeIf { CODE.matches(it) }?.let(::BattleInvite)
                "clan" -> uuid(p[1])?.let(::Clan)
                "u" -> p[1].takeIf { USERNAME.matches(it) }?.let(::User)
                "leaderboard" -> p[1].takeIf { it in BOARDS }?.let(::Leaderboard)
                "settings" -> if (p[1] == "alarm-health") AlarmHealth else null
                else -> null
            }
            3 -> when {
                p[0] == "battle" && p[1] == "invite" -> p[2].takeIf { CODE.matches(it) }?.let(::BattleInvite)
                p[0] == "clan" && p[1] == "war" -> uuid(p[2])?.let(::ClanWar)
                else -> null
            }
            else -> null
        }

        private fun uuid(s: String): UUID? =
            runCatching { UUID.fromString(s) }.getOrNull()?.takeIf { it.toString().equals(s, ignoreCase = true) }
    }
}
