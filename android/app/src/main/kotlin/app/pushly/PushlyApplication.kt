package app.pushly

import android.app.Application
import android.util.Log
import app.pushly.core.common.PLog
import app.pushly.feature.alarm.AlarmIntegrityWorker
import app.pushly.feature.alarm.AlarmNotifications
import app.pushly.feature.alarm.AlarmSystem

/**
 * Process start: logging first (receivers and the ring service run without any activity), then alarm housekeeping.
 * Alarms are re-armed on every process start — cheap, idempotent and the best defence against lost alarms.
 */
class PushlyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        PLog.debugEnabled = BuildConfig.DEBUG
        PLog.sink = PLog.Sink { level, category, message ->
            val tag = "Pushly/${category.name}"
            when (level) {
                PLog.Level.Debug -> Log.d(tag, message)
                PLog.Level.Info -> Log.i(tag, message)
                PLog.Level.Warning -> Log.w(tag, message)
                PLog.Level.Error -> Log.e(tag, message)
            }
        }
        AlarmNotifications.ensureChannels(this)
        AlarmSystem.get(this).scheduler.sync()
        AlarmIntegrityWorker.ensureScheduled(this)
    }
}
