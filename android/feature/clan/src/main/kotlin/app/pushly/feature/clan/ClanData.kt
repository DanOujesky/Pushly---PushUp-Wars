package app.pushly.feature.clan

import app.pushly.core.designsystem.ClanBadgeStyle
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
    /** Shape + colour + emblem (D-074); empty for clans that never picked one. */
    val badge: ClanBadgeStyle? = null,
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
data class MemberCard(
    val id: String,
    val username: String,
    val avatarPreset: String? = null,
    val trophies: Int? = null,
    val level: Int? = null,
    /** Pushly Pro — PRO badge (D-073). */
    val pro: Boolean? = null,
    /** Pro profile frame (D-074). */
    val frame: String? = null,
)

/** `get_clan_war_state()` (clan-war-state.schema.json, D-078): the lobby / live war and the latest finished war. */
@Serializable
data class ClanWarState(val current: ClanWar? = null, val last: ClanWar? = null) {
    companion object {
        fun decode(json: String): ClanWarState? {
            val el = ClanJson.parseToJsonElement(json)
            if (el is JsonNull || el !is JsonObject) return null
            return ClanJson.decodeFromJsonElement(serializer(), el)
        }
    }
}

/** One Clan War of 2–4 clans (D-078): lobby → live (Mon 00:00 UTC) → finished (Sun 20:00 UTC). Same as iOS. */
@Serializable
data class ClanWar(
    val id: String,
    /** lobby | live | finished */
    val status: String,
    val weekStart: String,
    val startsAt: String,
    val endsAt: String,
    val movedWeeks: Int = 0,
    val clans: List<Standing> = emptyList(),
    val result: Result? = null,
    val myToday: Today = Today(0, 0, 200, 400),
    val top: List<Top> = emptyList(),
    val feed: List<FeedItem> = emptyList(),
    val rally: Rally? = null,
) {
    @Serializable data class Today(val raw: Int, val counted: Int, val fullCap: Int, val halfCap: Int)
    @Serializable data class Top(val user: MemberCard, val reps: Int)
    @Serializable data class Stakes(val win: Int, val last: Int)
    @Serializable data class Standing(
        val clan: ClanSummary,
        val score: Int,
        val isMine: Boolean,
        val rank: Int? = null,
        val ratingDelta: Int? = null,
        val stakes: Stakes? = null,
        val mvp: MemberCard? = null,
    )
    @Serializable data class FeedItem(val clanId: String, val clanName: String, val mine: Boolean, val username: String, val points: Int, val at: String)
    @Serializable data class Rally(val available: Boolean, val nextAt: String? = null)
    @Serializable data class Result(val rank: Int, val of: Int, val ratingDelta: Int)

    val isLobby: Boolean get() = status == "lobby"
    val isLive: Boolean get() = status == "live"
    val isFinished: Boolean get() = status == "finished"
    val mine: Standing? get() = clans.firstOrNull { it.isMine }
    val rivals: List<Standing> get() = clans.filter { !it.isMine }

    /** My score minus the best other clan (positive = I lead). */
    val gap: Int get() = (mine?.score ?: 0) - (rivals.maxOfOrNull { it.score } ?: 0)
    val myRank: Int? get() = mine?.rank
}

/** `get_clan()` (clan.schema.json): summary fields + members, requests, war state (D-078). */
data class ClanHome(val summary: ClanSummary, val members: List<Member>, val requests: List<Request>, val warState: ClanWarState?) {
    @Serializable data class Member(val user: MemberCard, val role: String, val repsToday: Int = 0, val warReps: Int = 0)
    @Serializable data class Request(val user: MemberCard, val message: String? = null)

    /** The war on screen: lobby or live. */
    val war: ClanWar? get() = warState?.current

    @Serializable private data class Rest(
        val members: List<Member> = emptyList(),
        val requests: List<Request> = emptyList(),
        val warState: ClanWarState? = null,
    )

    companion object {
        /** null when the user isn't in a clan (the RPC returns JSON null). */
        fun decode(json: String): ClanHome? {
            val el = ClanJson.parseToJsonElement(json)
            if (el is JsonNull || el !is JsonObject) return null
            val summary = ClanJson.decodeFromJsonElement(ClanSummary.serializer(), el.jsonObject)
            val rest = ClanJson.decodeFromJsonElement(Rest.serializer(), el.jsonObject)
            return ClanHome(summary, rest.members, rest.requests, rest.warState)
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

/** One finished war of my clan (clan-war-results.schema.json, D-078). Same as iOS ClanWarResult. */
@Serializable
data class ClanWarResult(
    val id: String,
    val weekStart: String,
    val rank: Int,
    val of: Int,
    val score: Int,
    val ratingDelta: Int,
    val clans: List<Clan> = emptyList(),
) {
    @Serializable data class Clan(
        val id: String,
        val name: String,
        val tag: String,
        val badge: ClanBadgeStyle? = null,
        val score: Int,
        val rank: Int? = null,
        val isMine: Boolean,
    )

    /** W = 1st of a real war, L otherwise. */
    val letter: String get() = if (rank == 1 && of > 1) "W" else "L"

    companion object {
        fun decodeList(json: String): List<ClanWarResult> = ClanJson.decodeFromString(ListSerializer(serializer()), json)
    }
}

/** War Chests (war-chests.schema.json): earned, fixed content (XP), shown before opening. */
@Serializable
data class WarChests(val unopened: List<Chest> = emptyList(), val medals: Medals = Medals()) {
    @Serializable data class Chest(val id: String, val tier: String, val xp: Int, val clanName: String? = null, val weekStart: String? = null)
    @Serializable data class Medals(val gold: Int = 0, val silver: Int = 0, val bronze: Int = 0)

    val isEmpty: Boolean get() = unopened.isEmpty() && medals.gold + medals.silver + medals.bronze == 0

    companion object {
        fun decode(json: String): WarChests = ClanJson.decodeFromString(serializer(), json)
    }
}

object WarStreak {
    /** Current streak from the newest war: ("W", 3) = three wins (1st places) in a row. */
    fun current(wars: List<ClanWarResult>): Pair<String, Int>? {
        val first = wars.firstOrNull() ?: return null
        return first.letter to wars.takeWhile { it.letter == first.letter }.size
    }
}

/** Grouping rules for the clan chat (D-076). Same as iOS `ChatLayout`. */
/** "2 d 4 h" pieces until an ISO instant: (days, hours, minutes), null when passed. Same as iOS `WarClock`. */
object WarClock {
    fun until(iso: String, nowMs: Long = System.currentTimeMillis()): Triple<Int, Int, Int>? {
        val end = runCatching { java.time.Instant.parse(iso).toEpochMilli() }.getOrNull() ?: return null
        val s = (end - nowMs) / 1000
        if (s <= 0) return null
        return Triple((s / 86400).toInt(), ((s % 86400) / 3600).toInt(), ((s % 3600) / 60).toInt())
    }
}

object ChatLayout {
    fun instant(iso: String): java.time.Instant? = runCatching { java.time.OffsetDateTime.parse(iso).toInstant() }.getOrNull()

    /** A day separator goes above the first message of every local day. */
    fun newDay(msg: ClanMessage, prev: ClanMessage?, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): Boolean {
        val d = instant(msg.createdAt) ?: return false
        val p = prev?.let { instant(it.createdAt) } ?: return true
        return d.atZone(zone).toLocalDate() != p.atZone(zone).toLocalDate()
    }

    /** Name + avatar only on the first of consecutive messages by the same person within 5 minutes. */
    fun startsGroup(msg: ClanMessage, prev: ClanMessage?): Boolean {
        if (prev == null || prev.kind == "system" || msg.kind == "system" || prev.user?.id != msg.user?.id) return true
        val d = instant(msg.createdAt) ?: return true
        val p = instant(prev.createdAt) ?: return true
        return d.epochSecond - p.epochSecond > 300
    }
}
