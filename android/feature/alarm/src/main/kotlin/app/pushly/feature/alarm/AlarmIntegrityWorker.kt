package app.pushly.feature.alarm

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.pushly.core.common.PLog
import java.util.concurrent.TimeUnit

/** Daily safety net (doc 04 §6.2): re-arms alarms in case the OS or an OEM battery manager dropped them. */
class AlarmIntegrityWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val system = AlarmSystem.get(applicationContext)
        val report = system.scheduler.sync()
        PLog.info(PLog.Category.Alarm) { "Integrity check: armed ${report.armed.size}, blocked=${report.blocked}" }
        return Result.success()
    }

    companion object {
        private const val NAME = "alarm-integrity"

        fun ensureScheduled(context: Context) {
            runCatching {
                val request = PeriodicWorkRequestBuilder<AlarmIntegrityWorker>(1, TimeUnit.DAYS).build()
                WorkManager.getInstance(context).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
            }.onFailure { PLog.warning(PLog.Category.Alarm) { "Integrity worker not scheduled: ${it.message}" } }
        }
    }
}
