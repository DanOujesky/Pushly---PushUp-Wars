package app.pushly.feature.social

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

internal val SocialJson = Json { ignoreUnknownKeys = true }

/** Another user (shared/contracts/user-card.schema.json). Same as iOS. */
@Serializable
data class UserCard(
    val id: String,
    val username: String,
    val avatarPreset: String? = null,
    val country: String? = null,
    val level: Int = 1,
    val trophies: Int = 0,
    val streak: Int? = null,
    /** Only in search results: none | friends | incoming | outgoing. */
    val relation: String? = null,
    val clanTag: String? = null,
    /** Pushly Pro — PRO badge (D-073). */
    val pro: Boolean? = null,
) {
    companion object {
        fun decodeList(json: String): List<UserCard> = SocialJson.decodeFromString(ListSerializer(serializer()), json)
    }
}

/** `list_friends()` (friends.schema.json). */
@Serializable
data class FriendsList(
    val friends: List<UserCard> = emptyList(),
    val incoming: List<UserCard> = emptyList(),
    val outgoing: List<UserCard> = emptyList(),
    val blocked: List<Blocked> = emptyList(),
) {
    @Serializable data class Blocked(val id: String, val username: String)

    companion object {
        fun decode(json: String): FriendsList = SocialJson.decodeFromString(serializer(), json)
    }
}

/** One row of `get_friend_feed()` (friend-feed.schema.json). */
@Serializable
data class FeedItem(
    val id: Long,
    val user: UserCard,
    val kind: String,
    val payload: Map<String, JsonElement> = emptyMap(),
    val createdAt: String,
    val kudos: Int,
    val kudosByMe: Boolean,
) {
    fun int(key: String): Int = (payload[key] as? JsonPrimitive)?.intOrNull ?: 0
    fun text(key: String): String = (payload[key] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: ""

    companion object {
        fun decodeList(json: String): List<FeedItem> = SocialJson.decodeFromString(ListSerializer(serializer()), json)
    }
}

/** `get_leaderboard(board, scope, period)` (leaderboard.schema.json). */
@Serializable
data class Leaderboard(
    val board: String,
    val scope: String,
    val period: String,
    val periodKey: String,
    val refreshedAt: String? = null,
    val needsCountry: Boolean? = null,
    val rows: List<Row> = emptyList(),
    val around: List<Row> = emptyList(),
    val me: Me? = null,
) {
    @Serializable data class Row(val rank: Int, val score: Long, val isMe: Boolean, val user: User)

    /** Anonymous rows have no id or name. */
    @Serializable data class User(
        val id: String? = null,
        val username: String? = null,
        val avatarPreset: String? = null,
        val country: String? = null,
        val level: Int? = null,
        val streak: Int? = null,
        val anonymous: Boolean? = null,
        val pro: Boolean? = null,
    )

    @Serializable data class Me(val rank: Int, val score: Long, val shadow: Boolean)

    /** The own row to pin at the bottom when it isn't in the top list. */
    val pinnedMe: Row?
        get() {
            val m = me ?: return null
            if (rows.any { it.isMe }) return null
            return around.firstOrNull { it.isMe } ?: Row(m.rank, m.score, true, User())
        }

    companion object {
        fun decode(json: String): Leaderboard = SocialJson.decodeFromString(serializer(), json)
    }
}

/** Boards (doc 08 §4). Battles and clans come with phases 7 / 8. */
enum class Board(val wire: String, val periods: List<String>) {
    Wake("wake", listOf("week", "month", "all")),
    Streak("streak", listOf("current")),
    Reps("reps", listOf("day", "week", "month", "all"));

    val defaultPeriod: String get() = if (this == Streak) "current" else "week"
}

/** Another player's profile (user-profile.schema.json). [stats] is null when their visibility hides it. Same as iOS. */
@Serializable
data class UserProfile(
    val user: UserCard,
    /** self | friends | outgoing | incoming | none */
    val relation: String,
    val visible: Boolean,
    val league: League,
    val stats: Stats? = null,
    val headToHead: HeadToHead? = null,
) {
    @Serializable data class League(val league: String, val tier: String? = null)
    @Serializable data class Stats(
        val repsTotal: Int,
        val bestSet: Int,
        val bestStreak: Int,
        val achievements: Int,
        val bestTrophies: Int,
        val memberSince: String,
    )
    @Serializable data class HeadToHead(val wins: Int, val losses: Int, val draws: Int)

    companion object {
        /** null for JSON null (not found / blocked). */
        fun decode(json: String): UserProfile? =
            if (json.trim() == "null" || json.isBlank()) null else SocialJson.decodeFromString(serializer(), json)
    }
}
