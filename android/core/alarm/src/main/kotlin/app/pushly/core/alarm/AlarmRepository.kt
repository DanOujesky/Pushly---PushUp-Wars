package app.pushly.core.alarm

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Everything the alarm system keeps on the device, as one JSON document (decision D-035): the user's alarms,
 * changes waiting to be synced to the server, and the state of occurrences that are ringing right now.
 * Same document shape on iOS.
 */
@Serializable
data class AlarmDocument(
    val schemaVersion: Int = 1,
    val alarms: List<AlarmSchedule> = emptyList(),
    val outbox: List<OutboxEntry> = emptyList(),
    val active: List<RingState> = emptyList(),
)

/** A change waiting for `sync-alarms` (doc 04 §2, P2-09). The newest entry per alarm wins. */
@Serializable
data class OutboxEntry(val alarmId: String, val op: String, val version: Int, val queuedAt: String) {
    companion object {
        const val UPSERT = "upsert"
        const val DELETE = "delete"
    }
}

/** Reads and atomically writes the document (Android: device-protected storage, so it works before first unlock). */
interface DocumentStore {
    fun read(): String?
    fun write(content: String)
}

class InMemoryDocumentStore(var content: String? = null) : DocumentStore {
    override fun read(): String? = content
    override fun write(content: String) {
        this.content = content
    }
}

sealed interface SaveResult {
    data class Saved(val schedule: AlarmSchedule) : SaveResult
    data class Invalid(val errors: Set<String>) : SaveResult
    data object TooManyAlarms : SaveResult
}

/**
 * The single source of truth for alarms on the device. Works offline and without an account (CLAUDE.md §4.4).
 * Every mutation is persisted before it returns; the scheduler re-syncs from [alarms].
 */
class AlarmRepository(private val store: DocumentStore, private val now: () -> Instant = Instant::now) {
    private val lock = Any()
    private val _document = MutableStateFlow(load())
    val document: StateFlow<AlarmDocument> = _document.asStateFlow()
    private val _alarms = MutableStateFlow(_document.value.alarms)
    val alarms: StateFlow<List<AlarmSchedule>> = _alarms.asStateFlow()

    private fun load(): AlarmDocument = store.read()?.let { raw ->
        runCatching { JSON.decodeFromString(AlarmDocument.serializer(), raw) }.getOrNull()
    } ?: AlarmDocument()

    private fun commit(doc: AlarmDocument) {
        store.write(JSON.encodeToString(AlarmDocument.serializer(), doc))
        _document.value = doc
        _alarms.value = doc.alarms
    }

    fun alarm(id: String): AlarmSchedule? = _alarms.value.firstOrNull { it.id == id }

    /** Validates, bumps the version of an existing alarm, persists and queues it for sync. */
    fun save(schedule: AlarmSchedule, zone: ZoneId = ZoneId.systemDefault()): SaveResult = synchronized(lock) {
        val doc = _document.value
        val today = now().atZone(zone).toLocalDate()
        val existing = doc.alarms.firstOrNull { it.id == schedule.id }
        if (existing == null && doc.alarms.size >= AlarmSchedule.MAX_ALARMS_PER_USER) return SaveResult.TooManyAlarms
        val cleaned = schedule.copy(
            label = schedule.label.trim().take(AlarmSchedule.MAX_LABEL_LENGTH),
            overrides = schedule.overrides.filter { o -> AlarmValidation.parseDate(o.date)?.let { it >= today } ?: false },
        )
        val errors = AlarmValidation.errors(cleaned, today)
        if (errors.isNotEmpty()) return SaveResult.Invalid(errors)
        val saved = cleaned.copy(version = (existing?.version ?: 0) + 1, updatedAt = now().toString())
        val alarms = if (existing == null) doc.alarms + saved else doc.alarms.map { if (it.id == saved.id) saved else it }
        commit(doc.copy(alarms = alarms, outbox = queue(doc.outbox, saved.id, OutboxEntry.UPSERT, saved.version)))
        SaveResult.Saved(saved)
    }

    fun delete(id: String) = synchronized(lock) {
        val doc = _document.value
        val existing = doc.alarms.firstOrNull { it.id == id } ?: return@synchronized
        commit(
            doc.copy(
                alarms = doc.alarms.filterNot { it.id == id },
                outbox = queue(doc.outbox, id, OutboxEntry.DELETE, existing.version + 1),
                active = doc.active.filterNot { it.alarmId == id },
            ),
        )
    }

    fun setEnabled(id: String, enabled: Boolean, zone: ZoneId = ZoneId.systemDefault()): SaveResult? =
        alarm(id)?.let { save(it.copy(enabled = enabled), zone) }

    /** Skips the next ring of [id] (PS-24): adds a skip override for its local date. */
    fun skipNext(id: String, zone: ZoneId = ZoneId.systemDefault()): SaveResult? {
        val s = alarm(id) ?: return null
        if (s.kind == AlarmKind.OneOff) return save(s.copy(enabled = false), zone)
        val next = AlarmOccurrences.next(s, now(), zone) ?: return null
        val date = next.localDate.toString()
        val overrides = s.overrides.filterNot { it.date == date } + AlarmOverride(date = date, skip = true)
        return save(s.copy(overrides = overrides), zone)
    }

    /** Removes a skip on [date] (undo "skip next"). */
    fun unskip(id: String, date: LocalDate, zone: ZoneId = ZoneId.systemDefault()): SaveResult? {
        val s = alarm(id) ?: return null
        return save(s.copy(overrides = s.overrides.filterNot { it.date == date.toString() && it.skip == true }), zone)
    }

    /** Outbox entries the server has accepted are removed (only if no newer change was queued meanwhile). */
    fun acknowledge(entries: List<OutboxEntry>) = synchronized(lock) {
        val doc = _document.value
        commit(doc.copy(outbox = doc.outbox.filterNot { e -> entries.any { it.alarmId == e.alarmId && it.version >= e.version } }))
    }

    // ------------------------------------------------------------------ ringing occurrences

    fun activeRings(): List<RingState> = _document.value.active

    fun putRing(state: RingState) = synchronized(lock) {
        val doc = _document.value
        commit(doc.copy(active = doc.active.filterNot { it.occurrenceId == state.occurrenceId } + state))
    }

    fun removeRing(occurrenceId: String) = synchronized(lock) {
        val doc = _document.value
        if (doc.active.none { it.occurrenceId == occurrenceId }) return@synchronized
        commit(doc.copy(active = doc.active.filterNot { it.occurrenceId == occurrenceId }))
    }

    /** Drops ring states whose deadline passed (they can no longer be completed). */
    fun pruneRings(at: Instant = now()) = synchronized(lock) {
        val doc = _document.value
        val kept = doc.active.filter { it.deadline.isAfter(at) }
        if (kept.size != doc.active.size) commit(doc.copy(active = kept))
    }

    private fun queue(outbox: List<OutboxEntry>, id: String, op: String, version: Int): List<OutboxEntry> =
        outbox.filterNot { it.alarmId == id } + OutboxEntry(id, op, version, now().toString())

    companion object {
        val JSON = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }
    }
}
