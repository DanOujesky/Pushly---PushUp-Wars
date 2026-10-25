package app.pushly.feature.wakeflow

import android.content.Context
import android.content.SharedPreferences
import app.pushly.feature.wakeflow.generated.WorkoutPreset
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.util.UUID

/** Kind of a workout set (D-069). */
@Serializable
enum class SetKind {
    /** Ends when `target` push-ups are done. */
    @SerialName("reps") REPS,

    /** As many as possible: ends only when the user taps End set. */
    @SerialName("amrap") AMRAP,

    /** Ends after `target` seconds. */
    @SerialName("timed") TIMED,
}

/** One set: reps → push-ups, timed → seconds, amrap → 0; rest after it in seconds. */
@Serializable
data class WorkoutSet(val kind: SetKind, val target: Int, val restS: Int)

/**
 * A workout plan (D-069, contract shared/contracts/workout.schema.json) — same as iOS `Workout`. Presets are generated
 * from shared/workouts/presets.json; the user's own are kept on the device ([WorkoutStore]).
 */
@Serializable
data class Workout(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val description: String = "",
    /** EMOM: every set starts `everyS` seconds after the previous one (restS is ignored). */
    val everyS: Int? = null,
    val sets: List<WorkoutSet>,
    @Transient val isPreset: Boolean = false,
) {
    /** Push-ups the plan asks for, or null when a set has no fixed count (AMRAP / timed). */
    val plannedReps: Int?
        get() = if (sets.all { it.kind == SetKind.REPS }) sets.sumOf { it.target } else null

    /** Rough length in seconds (reps sets assume 2 s per push-up). */
    val estimatedSeconds: Int
        get() {
            everyS?.let { return it * sets.size }
            return sets.withIndex().sumOf { (i, s) ->
                val work = when (s.kind) {
                    SetKind.REPS -> s.target * 2
                    SetKind.TIMED -> s.target
                    SetKind.AMRAP -> 45
                }
                work + if (i < sets.size - 1) s.restS else 0
            }
        }

    /** Problems that keep a user-made workout from being saved (empty = valid). Same codes as the reference. */
    val validationErrors: List<String>
        get() {
            val errs = ArrayList<String>()
            if (name.isBlank()) errs += "name"
            if (sets.isEmpty() || sets.size > MAX_SETS) errs += "sets"
            everyS?.let { if (it !in EVERY_RANGE) errs += "everyS" }
            sets.forEachIndexed { i, s ->
                val badTarget = when (s.kind) {
                    SetKind.REPS -> s.target !in 1..MAX_TARGET_REPS
                    SetKind.TIMED -> s.target !in TIMED_RANGE
                    SetKind.AMRAP -> s.target != 0
                }
                if (badTarget) errs += "sets[$i].target"
                if (everyS != null && s.kind != SetKind.REPS) errs += "sets[$i].kind"
                if (s.restS !in 0..MAX_REST_S) errs += "sets[$i].restS"
            }
            return errs
        }

    companion object {
        const val MAX_SETS = 20
        const val MAX_TARGET_REPS = 200
        val TIMED_RANGE = 5..600
        const val MAX_REST_S = 600
        val EVERY_RANGE = 20..300

        fun blank(): Workout = Workout(name = "", sets = List(3) { WorkoutSet(SetKind.REPS, 10, 60) })

        fun presets(context: Context): List<Workout> =
            app.pushly.feature.wakeflow.generated.WorkoutPresets.all.map { it.toWorkout(context) }
    }
}

fun WorkoutPreset.toWorkout(context: Context): Workout = Workout(
    id = id, name = context.getString(nameRes), description = context.getString(descriptionRes), everyS = everyS,
    sets = sets, isPreset = true,
)

/** The user's own workouts, kept on the device as one JSON document (prefs "pushly.workouts"). */
class WorkoutStore(private val prefs: SharedPreferences) {
    constructor(context: Context) : this(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE))

    fun load(): List<Workout> = prefs.getString(KEY, null)?.let {
        runCatching { JSON.decodeFromString(ListSerializer(Workout.serializer()), it) }.getOrNull()
    } ?: emptyList()

    fun save(list: List<Workout>) {
        prefs.edit().putString(KEY, JSON.encodeToString(ListSerializer(Workout.serializer()), list)).apply()
    }

    fun upsert(w: Workout): List<Workout> {
        val copy = w.copy(isPreset = false)
        val list = load().toMutableList()
        val i = list.indexOfFirst { it.id == w.id }
        if (i >= 0) list[i] = copy else list += copy
        save(list)
        return list
    }

    fun delete(id: String): List<Workout> = load().filter { it.id != id }.also { save(it) }

    companion object {
        const val PREFS = "pushly.workouts"
        const val KEY = "custom.v1"
        val JSON = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }
}
