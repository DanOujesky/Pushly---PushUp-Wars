package app.pushly.core.alarm

import java.security.MessageDigest
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** One OS alarm the app must have armed (doc 04 §5.2–5.3). */
data class PlannedAlarm(
    val osAlarmId: String,
    val occurrenceId: String,
    val alarmId: String,
    /** "main" or "nag1", "nag2", … */
    val role: String,
    val fireAt: Instant,
    val countsForChallenge: Boolean,
)

/** Desired OS alarms — pure; same results as tools/reference/pushly_ref/plan.py and iOS `AlarmPlan`. */
object AlarmPlan {
    /** Never change: alarms already armed on devices are matched by ids derived from it. */
    val NAMESPACE: UUID = UUID.fromString("6f1c2a52-8b9e-4c1e-9a43-2a1d5e0c7b11")
    val NAG_INTERVAL: Duration = Duration.ofMinutes(2)
    const val ANDROID_LOOKAHEAD_DAYS = 400

    fun osAlarmId(occurrenceId: String, role: String): String = uuid5(NAMESPACE, "$occurrenceId#$role").toString()

    /** Rolling window: main alarm per occurrence + nag chain for each day's challenge occurrence. */
    fun windowPlan(schedules: List<AlarmSchedule>, from: Instant, zone: ZoneId, windowDays: Int, nagCount: Int): List<PlannedAlarm> {
        val occ = AlarmOccurrences.all(schedules, from, zone, windowDays)
        val challengeIds = occ.map { it.localDate }.distinct()
            .mapNotNull { AlarmOccurrences.challengeOccurrence(it, occ)?.occurrenceId }.toSet()
        val out = ArrayList<PlannedAlarm>()
        for (o in occ) {
            out += entry(o, "main", o.instant)
            if (o.occurrenceId in challengeIds) {
                val deadline = o.instant.plus(AlarmOccurrences.DEADLINE)
                for (n in 1..nagCount) {
                    val at = o.instant.plus(NAG_INTERVAL.multipliedBy(n.toLong()))
                    if (at.isBefore(deadline)) out += entry(o, "nag$n", at)
                }
            }
        }
        return out.sortedWith(compareBy({ it.fireAt }, { it.osAlarmId }))
    }

    /** Android arms only the next occurrence of every alarm (doc 04 §6.2). Key = alarm id. */
    fun nextPerAlarm(schedules: List<AlarmSchedule>, from: Instant, zone: ZoneId): Map<String, Occurrence?> =
        schedules.associate { it.id to AlarmOccurrences.next(it, from, zone) }

    private fun entry(o: Occurrence, role: String, at: Instant) =
        PlannedAlarm(osAlarmId(o.occurrenceId, role), o.occurrenceId, o.alarmId, role, at, o.countsForChallenge)

    /** RFC 4122 name-based UUID, version 5 (SHA-1). */
    fun uuid5(namespace: UUID, name: String): UUID {
        val ns = ByteArray(16)
        for (i in 0 until 8) ns[i] = (namespace.mostSignificantBits ushr (56 - 8 * i)).toByte()
        for (i in 0 until 8) ns[8 + i] = (namespace.leastSignificantBits ushr (56 - 8 * i)).toByte()
        val hash = MessageDigest.getInstance("SHA-1").apply {
            update(ns)
            update(name.toByteArray(Charsets.UTF_8))
        }.digest()
        hash[6] = ((hash[6].toInt() and 0x0f) or 0x50).toByte()
        hash[8] = ((hash[8].toInt() and 0x3f) or 0x80).toByte()
        var msb = 0L
        var lsb = 0L
        for (i in 0 until 8) msb = (msb shl 8) or (hash[i].toLong() and 0xff)
        for (i in 8 until 16) lsb = (lsb shl 8) or (hash[i].toLong() and 0xff)
        return UUID(msb, lsb)
    }
}
