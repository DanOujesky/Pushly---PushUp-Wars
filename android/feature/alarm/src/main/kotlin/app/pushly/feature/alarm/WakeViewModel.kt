package app.pushly.feature.alarm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.alarm.AlarmOccurrences
import app.pushly.core.alarm.AlarmSchedule
import app.pushly.core.alarm.HealthIssue
import app.pushly.core.alarm.Occurrence
import app.pushly.core.alarm.SaveResult
import app.pushly.core.alarm.WakeSummary
import app.pushly.core.common.PLog
import app.pushly.feature.wakeflow.SessionServices
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Wake tab + editor state (UDF). All alarm writes go through the repository, then the scheduler re-syncs. */
class WakeViewModel(app: Application) : AndroidViewModel(app) {
    private val system = AlarmSystem.get(app)
    private val now = MutableStateFlow(Instant.now())
    private val _health = MutableStateFlow<List<HealthIssue>>(emptyList())
    val health: StateFlow<List<HealthIssue>> = _health.asStateFlow()
    private val _notice = MutableStateFlow<Int?>(null)
    val notice: StateFlow<Int?> = _notice.asStateFlow()
    private val _summary = MutableStateFlow<WakeSummary?>(null)

    /** Server view of the challenge (streak, recent days, today) — null until loaded / signed out (PS-10, PS-13). */
    val summary: StateFlow<WakeSummary?> = _summary.asStateFlow()

    /** Sessions waiting for the server (PS-90). */
    val pendingSessions: StateFlow<Set<String>> = SessionServices.shared?.uploader?.pending ?: MutableStateFlow(emptySet())

    data class Item(val schedule: AlarmSchedule, val next: Occurrence?, val skippedDate: String?)

    data class State(val items: List<Item> = emptyList(), val next: Occurrence? = null, val now: Instant = Instant.now())

    val state: StateFlow<State> = combine(system.repository.alarms, now) { alarms, at ->
        val zone = ZoneId.systemDefault()
        val items = alarms.map { s ->
            val next = if (s.enabled) AlarmOccurrences.next(s, at, zone) else null
            val today = at.atZone(zone).toLocalDate().toString()
            val skipped = s.overrides.filter { it.skip == true && it.date >= today }.minByOrNull { it.date }?.date
            Item(s, next, skipped)
        }
        State(items, items.mapNotNull { it.next }.minByOrNull { it.instant }, at)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, State())

    init {
        // Widgets follow the next ring (edits, skips, an alarm that just rang).
        viewModelScope.launch {
            state.map { it.next?.occurrenceId }.distinctUntilChanged().collect { WidgetData.refresh(getApplication()) }
        }
        viewModelScope.launch {
            while (true) {
                delay(30_000)
                now.value = Instant.now()
            }
        }
    }

    /** Re-read OS state (called on every resume) and repair the schedule if needed. */
    fun refresh() {
        now.value = Instant.now()
        system.scheduler.sync()
        // Server sync (outbox upload, restore on a new phone); the OS schedule always comes from local data.
        viewModelScope.launch {
            if (system.sync.syncIfNeeded()) system.scheduler.sync()
        }
        viewModelScope.launch {
            val services = SessionServices.shared ?: return@launch
            services.uploader.flush()
            val fetch = services.summary ?: return@launch
            try {
                val summary = WakeSummary.decode(fetch())
                _summary.value = summary
                WidgetData.saveSummary(getApplication(), summary)
                WidgetData.refresh(getApplication())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PLog.warning(PLog.Category.Sync) { "Wake summary not loaded: ${e.message}" }
            }
        }
        AlarmIntegrityWorker.ensureScheduled(getApplication())
        AlarmRingService.resumeIfNeeded(getApplication())
        _health.value = AlarmPermissions.health(getApplication())
        val critical = _health.value.any { it.severity == app.pushly.core.alarm.HealthSeverity.Critical }
        system.scheduler.armHealthReminder(
            app.pushly.core.alarm.AlarmHealth.eveningReminder(critical, state.value.next?.instant, Instant.now(), ZoneId.systemDefault()),
        )
    }

    fun newSchedule(): AlarmSchedule = AlarmSchedule.newDefault(UUID.randomUUID().toString())

    fun canAddAlarm(): Boolean = system.repository.alarms.value.size < AlarmSchedule.MAX_ALARMS_PER_USER

    fun save(schedule: AlarmSchedule): SaveResult {
        val result = system.repository.save(schedule)
        if (result is SaveResult.Saved) refresh()
        return result
    }

    fun delete(id: String) {
        system.repository.delete(id)
        refresh()
    }

    fun setEnabled(id: String, enabled: Boolean) {
        system.repository.setEnabled(id, enabled)
        refresh()
    }

    fun skipNext(id: String) {
        system.repository.skipNext(id)
        refresh()
    }

    fun undoSkip(id: String, date: String) {
        system.repository.unskip(id, java.time.LocalDate.parse(date))
        refresh()
    }

    fun testAlarm(schedule: AlarmSchedule) {
        _notice.value = if (system.scheduler.armPractice(schedule)) R.string.wake_test_armed else R.string.wake_test_failed
    }

    fun clearNotice() {
        _notice.value = null
    }

    fun missingPermissions(): List<AlarmPermissions.Step> = AlarmPermissions.missingRequired(getApplication())
}
