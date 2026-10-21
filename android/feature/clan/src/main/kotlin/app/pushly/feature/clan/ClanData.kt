package app.pushly.feature.clan

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

internal val ClanJson = Json { ignoreUnknownKeys = true }

/** A clan in lists (clan-summary.schema.json). Same as iOS. */
@Serializable
data class ClanSummary(
    val id: String,
    val name: String,
    val tag: String,
    val description: String = "",
    val joinPolicy: String = "open",
    val minTrophies: Int = 0,
    val country: String? = null,
    val warEnabled: Boolean = true,
    val rating: Int = 1000,
    val memberCount: Int = 0,
    val maxMembers: Int = 30,
    val myRole: String? = null,
    val requested: Boolean = false,
) {
    companion object {
        fun decodeList(json: String): List<ClanSummary> = ClanJson.decodeFromString(ListSerializer(serializer()), json)
    }
}

@Serializable
data class MemberCard(val id: String, val username: String, val avatarPreset: String? = null, val trophies: Int? = null, val level: Int? = null)

/** War card (clan-war.schema.json). */
@Serializable
data class ClanWar(
    val id: String,
    val status: String,
    val weekStart: String,
    val endsAt: String,
    val opponent: ClanSummary? = null,
    val score: Score,
    val myToday: Today,
    val top: List<Top> = emptyList(),
) {
    @Serializable data class Score(val us: Int, val them: Int)
    @Serializable data class Today(val raw: Int, val counted: Int, val fullCap: Int, val halfCap: Int)
    @Serializable data class Top(val user: MemberCard, val reps: Int)
}

/** `get_clan()` (clan.schema.json): summary fields + members, requests, war. */
data class ClanHome(val summary: ClanSummary, val members: List<Member>, val requests: List<Request>, val war: ClanWar?) {
    @Serializable data class Member(val user: MemberCard, val role: String, val repsToday: Int = 0, val warReps: Int = 0)
    @Serializable data class Request(val user: MemberCard, val message: String? = null)

    @Serializable private data class Rest(val members: List<Member> = emptyList(), val requests: List<Request> = emptyList(), val war: ClanWar? = null)

    companion object {
        /** null when the user isn't in a clan (the RPC returns JSON null). */
        fun decode(json: String): ClanHome? {
            val el = ClanJson.parseToJsonElement(json)
            if (el is JsonNull || el !is JsonObject) return null
            val summary = ClanJson.decodeFromJsonElement(ClanSummary.serializer(), el.jsonObject)
            val rest = ClanJson.decodeFromJsonElement(Rest.serializer(), el.jsonObject)
            return ClanHome(summary, rest.members, rest.requests, rest.war)
        }
    }
}

/** One chat message (clan-messages.schema.json). */
@Serializable
data class ClanMessage(val id: Long, val kind: String, val body: String? = null, val user: Author? = null, val createdAt: String) {
    @Serializable data class Author(val id: String, val username: String, val avatarPreset: String? = null)

    companion object {
        fun decodeList(json: String): List<ClanMessage> = ClanJson.decodeFromString(ListSerializer(serializer()), json)
    }
}

/** Roles and what they may do (doc 09 §2) — mirrors the server checks. Same as iOS ClanRole. */
enum class ClanRole(val wire: String, val rank: Int) {
    Leader("leader", 4), CoLeader("co_leader", 3), Elder("elder", 2), Member("member", 1);

    val canEditSettings: Boolean get() = rank >= 3
    val canAcceptRequests: Boolean get() = rank >= 2

    fun canKick(other: ClanRole): Boolean = rank >= 2 && other.rank < rank

    fun assignable(other: ClanRole): List<ClanRole> = when {
        this == Leader -> listOf(CoLeader, Elder, Member).filter { it != other }
        this == CoLeader && other.rank <= 2 -> listOf(Elder, Member).filter { it != other }
        else -> emptyList()
    }

    companion object {
        fun of(wire: String?): ClanRole? = entries.firstOrNull { it.wire == wire }
    }
}
