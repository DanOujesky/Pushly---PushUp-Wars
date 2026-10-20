package app.pushly.feature.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import app.pushly.core.alarm.AlarmOccurrences
import app.pushly.core.alarm.AlarmRepository
import app.pushly.core.alarm.AlarmSchedule
import app.pushly.core.common.PLog
import java.time.Instant
import java.time.ZoneId

/**
 * The only class that talks to AlarmManager (CLAUDE.md §10). Arms the next occurrence of every enabled alarm with
 * `setAlarmClock` (exact, works in Doze, shows the alarm icon), plus escalation snoozes and practice alarms.
 * [sync] is idempotent: it re-arms everything desired and cancels whatever it armed before that is no longer wanted.
 */
class AlarmScheduler(
    private val context: Context,
    deviceContext: Context,
    private val repository: AlarmRepository,
) {
    data class Armed(val key: String, val fireAt: Instant, val occurrenceId: String, val alarmId: String)

    data class SyncReport(val armed: List<Armed>, val cancelled: List<String>, val blocked: Boolean)

    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val record = deviceContext.getSharedPreferences("alarm_scheduler", Context.MODE_PRIVATE)

    fun canScheduleExact(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    /** What should be armed right now. */
    fun desired(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<Armed> {
        val out = ArrayList<Armed>()
        for (s in repository.alarms.value.filter(AlarmSchedule::enabled)) {
            val next = AlarmOccurrences.next(s, now, zone) ?: continue
            out += Armed("alarm:${s.id}", next.instant, next.occurrenceId, s.id)
        }
        for (ring in repository.activeRings()) {
            val until = ring.snoozedUntil?.let(Instant::parse) ?: continue
            if (until.isAfter(now)) out += Armed("snooze:${ring.occurrenceId}", until, ring.occurrenceId, ring.alarmId)
        }
        recorded().filter { it.key.startsWith(PRACTICE) && it.fireAt.isAfter(now) }.forEach { out += it }
        return out
    }

    @Synchronized
    fun sync(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): SyncReport {
        repository.pruneRings(now)
        val desired = desired(now, zone)
        val previous = recorded()
        val cancelled = previous.filter { p -> desired.none { it.key == p.key } }.map { it.key }
        cancelled.forEach { key -> previous.firstOrNull { it.key == key }?.let(::cancel) }
        if (!canScheduleExact()) {
            PLog.warning(PLog.Category.Alarm) { "Exact alarms not allowed — ${desired.size} alarms cannot be armed" }
            saveRecord(emptyList())
            return SyncReport(emptyList(), cancelled, blocked = true)
        }
        val armed = desired.filter(::arm)
        saveRecord(armed)
        PLog.info(PLog.Category.Alarm) { "Alarm sync: armed ${armed.size}, cancelled ${cancelled.size}" }
        return SyncReport(armed, cancelled, blocked = armed.size < desired.size)
    }

    /** "Test my alarm" (doc 04 §9): a practice ring in [delaySeconds] with the given alarm's settings. */
    @Synchronized
    fun armPractice(schedule: AlarmSchedule, delaySeconds: Long = 10, now: Instant = Instant.now()): Boolean {
        val at = now.plusSeconds(delaySeconds)
        val item = Armed("$PRACTICE${schedule.id}", at, "practice:${schedule.id}:${at.epochSecond}", schedule.id)
        if (!canScheduleExact() || !arm(item)) return false
        record.edit().putString(KEY_PRACTICE_PREFIX + item.key, AlarmRepository.JSON.encodeToString(AlarmSchedule.serializer(), schedule)).apply()
        saveRecord(recorded().filterNot { it.key == item.key } + item)
        return true
    }

    /** The (possibly unsaved) settings a practice alarm was armed with. */
    fun practiceSchedule(key: String): AlarmSchedule? = record.getString(KEY_PRACTICE_PREFIX + key, null)?.let {
        runCatching { AlarmRepository.JSON.decodeFromString(AlarmSchedule.serializer(), it) }.getOrNull()
    }

    /** True if the OS reports an armed alarm clock of ours when we expect one (health check §8). */
    fun nextAlarmArmed(now: Instant = Instant.now()): Boolean {
        if (desired(now).isEmpty()) return true
        return alarmManager.nextAlarmClock != null && recorded().isNotEmpty()
    }

    /**
     * Evening health reminder (doc 04 §8): an inexact wake-up at [at] (21:00) that re-checks health and notifies if
     * the alarm still can't ring; null cancels it. Inexact on purpose — it is a reminder, not the alarm.
     */
    @Synchronized
    fun armHealthReminder(at: Instant?) {
        val intent = Intent(context, HealthReminderReceiver::class.java).setAction(HealthReminderReceiver.ACTION)
        val pi = PendingIntent.getBroadcast(context, 1, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        if (at == null) {
            alarmManager.cancel(pi)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), pi)
        }
    }

    private fun arm(item: Armed): Boolean = try {
        val show = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.let { PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
        alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(item.fireAt.toEpochMilli(), show), operation(item))
        true
    } catch (e: SecurityException) {
        PLog.error(PLog.Category.Alarm) { "setAlarmClock refused for ${item.key}: ${e.message}" }
        false
    }

    private fun cancel(item: Armed) {
        alarmManager.cancel(operation(item))
    }

    private fun operation(item: Armed): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(AlarmReceiver.ACTION_RING)
            .setData(Uri.parse("pushly-alarm://${item.key}"))
            .putExtra(AlarmReceiver.EXTRA_KEY, item.key)
            .putExtra(AlarmReceiver.EXTRA_ALARM_ID, item.alarmId)
            .putExtra(AlarmReceiver.EXTRA_OCCURRENCE_ID, item.occurrenceId)
            .putExtra(AlarmReceiver.EXTRA_FIRE_AT, item.fireAt.toEpochMilli())
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun recorded(): List<Armed> = record.getStringSet(KEY_ARMED, emptySet()).orEmpty().mapNotNull { line ->
        val parts = line.split('|')
        if (parts.size != 4) return@mapNotNull null
        val millis = parts[1].toLongOrNull() ?: return@mapNotNull null
        Armed(parts[0], Instant.ofEpochMilli(millis), parts[2], parts[3])
    }

    private fun saveRecord(items: List<Armed>) {
        record.edit().putStringSet(KEY_ARMED, items.map { "${it.key}|${it.fireAt.toEpochMilli()}|${it.occurrenceId}|${it.alarmId}" }.toSet())
            .apply()
    }

    companion object {
        private const val KEY_ARMED = "armed"
        private const val KEY_PRACTICE_PREFIX = "schedule:"
        const val PRACTICE = "practice:"
    }
}
