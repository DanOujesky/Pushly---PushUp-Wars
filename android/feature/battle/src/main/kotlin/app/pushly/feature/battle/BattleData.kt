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
    /** Only in the start response of a ghost battle. */
    val ghostTimeline: List<BattleRules.Rep>? = null,
) {
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
    val theirScore: Int get() = if (me == "a") score.b else score.a
    val myTrophies: Int? get() = result?.trophies?.let { if (me == "a") it.a else it.b }
    val isOver: Boolean get() = status in setOf("settled", "cancelled", "void")

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

/** Modes offered in the app (doc 07 §2). Quick match: max reps 60 s and speed 20. */
enum class BattleMode(val wire: String, val variant: Map<String, Int>, val quickMatch: Boolean) {
    MaxReps("max_reps", mapOf("durationS" to 60), true),
    Speed("speed", mapOf("targetReps" to 20), true),
    Endurance("endurance", emptyMap(), false),
}
