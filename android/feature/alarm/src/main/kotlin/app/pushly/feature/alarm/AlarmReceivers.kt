package app.pushly.feature.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import app.pushly.core.common.PLog

/** Fired by AlarmManager at the ring time → starts the ring service as a foreground service immediately (doc 04 §6.3). */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RING) return
        val service = Intent(context, AlarmRingService::class.java)
            .setAction(AlarmRingService.ACTION_START)
            .putExtras(intent)
        try {
            ContextCompat.startForegroundService(context, service)
        } catch (e: IllegalStateException) {
            // Should not happen for alarm-clock broadcasts (they are exempt from FGS start limits); never fail silently.
            PLog.error(PLog.Category.Alarm) { "Could not start ring service: ${e.message}" }
            AlarmNotifications.showRingFallback(context, intent.getStringExtra(EXTRA_ALARM_ID))
        }
    }

    companion object {
        const val ACTION_RING = "app.pushly.alarm.RING"
        const val EXTRA_KEY = "key"
        const val EXTRA_ALARM_ID = "alarmId"
        const val EXTRA_OCCURRENCE_ID = "occurrenceId"
        const val EXTRA_FIRE_AT = "fireAt"
    }
}

/** Re-arms alarms after reboot (also before unlock), app update, clock/time-zone changes and permission changes (doc 04 §6.2). */
class AlarmEventsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PLog.info(PLog.Category.Alarm) { "Alarm event ${intent.action} → re-sync" }
        val system = AlarmSystem.get(context)
        system.scheduler.sync()
        AlarmIntegrityWorker.ensureScheduled(context)
        AlarmRingService.resumeIfNeeded(context)
    }
}
