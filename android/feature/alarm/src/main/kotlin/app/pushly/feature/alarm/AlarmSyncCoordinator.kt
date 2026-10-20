package app.pushly.feature.alarm

import app.pushly.core.alarm.AlarmRepository
import app.pushly.core.alarm.AlarmSync
import app.pushly.core.common.PLog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Duration
import java.time.Instant

/**
 * Uploads the alarm outbox to the server and restores alarms from it (roadmap P2-09). Only when signed in; alarms
 * never depend on it (CLAUDE.md §4.4). Throttled: runs when something is queued, or at most every 6 h to restore.
 * Same behaviour as iOS `AlarmSyncCoordinator`.
 */
class AlarmSyncCoordinator(
    private val repository: AlarmRepository,
    private val now: () -> Instant = Instant::now,
) {
    /** Returns the transport while signed in, null otherwise (set by the app — guest builds leave it null). */
    @Volatile var transport: (suspend () -> (suspend (String) -> String)?)? = null

    private val mutex = Mutex()
    @Volatile private var lastFullSync: Instant? = null

    /** True when the local alarms changed (restored or conflict resolved) and the scheduler must re-sync. */
    suspend fun syncIfNeeded(force: Boolean = false): Boolean {
        if (mutex.isLocked) return false
        return mutex.withLock {
            val last = lastFullSync
            val due = force || repository.document.value.outbox.isNotEmpty() ||
                last == null || Duration.between(last, now()) > Duration.ofHours(6)
            val send = if (due) transport?.invoke() else null
            if (send == null) return@withLock false
            val before = repository.alarms.value
            val (changes, sent) = AlarmSync.changes(repository.document.value)
            try {
                val response = AlarmSync.decode(send(AlarmSync.encode(changes)))
                repository.applySync(sent, response)
                lastFullSync = now()
                repository.alarms.value != before
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Offline or server down: keep the outbox, try again next time. Alarms keep working locally.
                PLog.warning(PLog.Category.Sync) { "Alarm sync failed: ${e.message}" }
                false
            }
        }
    }
}
