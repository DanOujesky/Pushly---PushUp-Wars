package app.pushly

import android.app.Application
import android.util.Log
import app.pushly.core.alarm.AlarmLog
import app.pushly.core.common.PLog
import app.pushly.feature.alarm.AlarmIntegrityWorker
import app.pushly.feature.alarm.AlarmNotifications
import app.pushly.feature.alarm.AlarmSystem
import app.pushly.feature.wakeflow.SessionServices
import app.pushly.feature.wakeflow.SessionUploader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File

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
        AlarmLog.sink = { message -> PLog.warning(PLog.Category.Alarm) { message } }
        AlarmNotifications.ensureChannels(this)
        AlarmSystem.get(this).scheduler.sync()
        AlarmIntegrityWorker.ensureScheduled(this)
        // Rep-log outbox (P4-05): queued offline / in guest mode, uploaded while signed in (transport set by MainActivity).
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        SessionServices.shared = SessionServices(
            SessionUploader(File(filesDir, "RepSessions"), scope),
            "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
        )
    }
}
