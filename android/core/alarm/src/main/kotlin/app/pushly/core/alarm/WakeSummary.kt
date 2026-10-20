package app.pushly.core.alarm

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** `get_wake_summary()` (shared/contracts/wake-summary.schema.json): today's challenge, streak and recent days. */
@Serializable
data class WakeSummary(
    val today: String,
    val plan: Plan,
    val streak: Streak,
    val attempts: List<Attempt> = emptyList(),
    val repsToday: Int? = null,
) {
    @Serializable data class Plan(val kind: String, val occurrenceId: String? = null, val t0: String? = null, val deadline: String? = null)

    @Serializable data class Streak(
        val current: Int,
        val best: Int,
        val pureCurrent: Int,
        val pureBest: Int,
        val freezesAvailable: Int,
        val lastCountedDate: String? = null,
    )

    @Serializable data class Attempt(
        val localDate: String,
        val status: String,
        val points: Int = 0,
        val reason: String? = null,
        val finalTargetReps: Int? = null,
        val score: Int? = null,
    )

    /** Status per local date (YYYY-MM-DD) for the week strip. */
    fun status(on: String): String? = attempts.firstOrNull { it.localDate == on }?.status

    companion object {
        private val JSON = Json { ignoreUnknownKeys = true }
        fun decode(json: String): WakeSummary = JSON.decodeFromString(serializer(), json)
    }
}
