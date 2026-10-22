package app.pushly.feature.battle

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

internal val BattleJson = Json { ignoreUnknownKeys = true; explicitNulls = false }

/** A battle as the caller sees it (battle.schema.json). Same as iOS. */
@Serializable
data class Battle(
    val id: String,
    val type: String,
    val mode: String,
    val variant: Map<String, Int> = emptyMap(),
    val ranked: Boolean,
    val status: String,
    val startAt: String? = null,
    val me: String,
    val opponent: Opponent,
    val ready: BoolPair = BoolPair(false, false),
    val score: IntPair = IntPair(0, 0),
    val result: Outcome? = null,
    val winner: String? = null,
    /** Ghost battle: the opponent is a recorded timeline (doc 07 §7). */
    val ghost: Boolean? = null,
    /** Practice bot level when the opponent is a labelled bot (D-063); null for people and recorded ghosts. */
    val bot: String? = null,
    /** Only in the start response of a ghost battle. */
    val ghostTimeline: List<BattleRules.Rep>? = null,
    /** ms since start of each side's latest rep (Turns window), migration 0020. */
    val lastRepT: LongPair? = null,
    /** Best of 3: reps per round so far (raw counts). */
    val rounds: List<IntPair>? = null,
) {
    @Serializable data class LongPair(val a: Long? = null, val b: Long? = null)
    @Serializable data class Opponent(val id: String? = null, val username: String, val avatarPreset: String? = null, val trophies: Int? = null)
    @Serializable data class IntPair(val a: Int, val b: Int)
    @Serializable data class BoolPair(val a: Boolean, val b: Boolean)

    @Serializable data class Outcome(
        val winner: String? = null,
        val reason: String,
        val a: BattleRules.Side,
        val b: BattleRules.Side,
        val counted: Boolean? = null,
        val trophies: IntPair? = null,
    )

    val myScore: Int get() = if (me == "a") score.a else score.b
    val theirLastRepT: Long? get() = lastRepT?.let { if (me == "a") it.b else it.a }
    val theirRounds: List<Int> get() = rounds.orEmpty().map { if (me == "a") it.b else it.a }
    val theirScore: Int get() = if (me == "a") score.b else score.a
    val myTrophies: Int? get() = result?.trophies?.let { if (me == "a") it.a else it.b }
    val isOver: Boolean get() = status in setOf("settled", "cancelled", "void")

    /** Opponent name for display: bots always carry the 🤖 so nobody mistakes them for a person. */
    val opponentDisplayName: String get() = if (bot == null) opponent.username else "🤖 " + opponent.username

    companion object {
        fun decode(json: String): Battle = BattleJson.decodeFromString(serializer(), json)
        fun decodeList(json: String): List<Battle> = BattleJson.decodeFromString(ListSerializer(serializer()), json)
    }
}

@Serializable
data class BattleInvites(val incoming: List<Incoming> = emptyList(), val outgoing: List<Outgoing> = emptyList()) {
    @Serializable data class Incoming(val id: String, val from: Battle.Opponent, val mode: String, val variant: Map<String, Int> = emptyMap(), val ranked: Boolean)
    @Serializable data class Outgoing(val id: String, val to: Battle.Opponent? = null, val code: String? = null, val mode: String, val status: String, val battleId: String? = null)

    companion object {
        fun decode(json: String): BattleInvites = BattleJson.decodeFromString(serializer(), json)
    }
}

@Serializable
data class MatchmakingStatus(val queued: Boolean, val battle: Battle? = null, val waitedS: Int? = null, val timedOut: Boolean? = null) {
    companion object {
        fun decode(json: String): MatchmakingStatus = BattleJson.decodeFromString(serializer(), json)
    }
}

@Serializable
data class FriendPick(val id: String, val username: String, val avatarPreset: String? = null)

@Serializable
internal data class FriendsPayload(val friends: List<FriendPick> = emptyList())

/** Modes offered in the app (doc 07 §2). Quick match: max reps 60 s, speed 20, best of 3; turns + endurance friend-only. */
enum class BattleMode(val wire: String, val variant: Map<String, Int>, val quickMatch: Boolean) {
    MaxReps("max_reps", mapOf("durationS" to 60), true),
    Speed("speed", mapOf("targetReps" to 20), true),
    BestOf3("best_of_3", emptyMap(), true),
    Turns("turns", emptyMap(), false),
    Endurance("endurance", emptyMap(), false),
    ;

    companion object {
        fun of(wire: String): BattleMode? = entries.firstOrNull { it.wire == wire }
    }
}

/** One archived season (season-history.schema.json): the badge is the best league reached. Same as iOS. */
@Serializable
data class SeasonResult(
    val seasonId: Int,
    val month: String,
    val finalTrophies: Int,
    val bestTrophies: Int,
    val league: String,
    val tier: String? = null,
    val rank: Int,
) {
    companion object {
        fun decodeList(json: String): List<SeasonResult> = BattleJson.decodeFromString(ListSerializer(serializer()), json)
    }
}

fun leagueGlyph(league: String): String = when (league) {
    "bronze" -> "🥉"
    "silver" -> "🥈"
    "gold" -> "🥇"
    "platinum" -> "💠"
    "diamond" -> "💎"
    "champion" -> "🏆"
    else -> "👑"
}

/** Practice bot levels (D-063), weakest first. Same as iOS `BotLevel`. */
enum class BotLevel(val wire: String, val title: Int, val pace: Int) {
    Beginner("beginner", R.string.bot_beginner, R.string.bot_pace_beginner),
    Rookie("rookie", R.string.bot_rookie, R.string.bot_pace_rookie),
    Athlete("athlete", R.string.bot_athlete, R.string.bot_pace_athlete),
    Pro("pro", R.string.bot_pro, R.string.bot_pace_pro),
    Champion("champion", R.string.bot_champion, R.string.bot_pace_champion),
    ;

    companion object {
        fun of(wire: String?): BotLevel? = entries.firstOrNull { it.wire == wire }
    }
}
