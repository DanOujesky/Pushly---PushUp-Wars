package app.pushly.core.alarm

/**
 * Idempotent scheduler diff (doc 04 §5.4): what to cancel and what to (re)schedule so the OS matches the plan.
 * [signature] captures everything that requires re-scheduling (fire time, title, sound, …). Same on iOS.
 */
object AlarmSyncDiff {
    data class Desired<T>(val key: String, val signature: String, val payload: T)

    data class Result<T>(val cancel: List<String>, val schedule: List<Desired<T>>) {
        val isEmpty: Boolean get() = cancel.isEmpty() && schedule.isEmpty()
    }

    /** [current] = key → signature of what the OS has armed now (according to the OS and our record of it). */
    fun <T> compute(desired: List<Desired<T>>, current: Map<String, String>): Result<T> {
        val wanted = desired.associateBy { it.key }
        val cancel = current.filter { (key, sig) -> wanted[key]?.signature != sig }.keys.sorted()
        val schedule = desired.filter { current[it.key] != it.signature }
        return Result(cancel, schedule)
    }
}
