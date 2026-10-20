package app.pushly.core.alarm

import kotlinx.serialization.Serializable

/** Wire format of `sync_alarms` (supabase migration 0005/0006, roadmap P2-09). Same as iOS `AlarmSync`. */
object AlarmSync {
    @Serializable
    data class Change(val op: String, val alarm: AlarmSchedule? = null, val id: String? = null, val version: Int? = null)

    @Serializable
    data class Result(
        val id: String? = null,
        val status: String,
        val version: Int? = null,
        val errors: List<String>? = null,
        val server: AlarmSchedule? = null,
    )

    @Serializable
    data class Response(val results: List<Result> = emptyList(), val alarms: List<AlarmSchedule> = emptyList())

    const val MAX_CHANGES_PER_CALL = 50

    /** The outbox as server changes (newest entry per alarm; upserts carry the current alarm). */
    fun changes(document: AlarmDocument): Pair<List<Change>, List<OutboxEntry>> {
        val changes = mutableListOf<Change>()
        val sent = mutableListOf<OutboxEntry>()
        for (entry in document.outbox.take(MAX_CHANGES_PER_CALL)) {
            if (entry.op == OutboxEntry.DELETE) {
                changes += Change(op = OutboxEntry.DELETE, id = entry.alarmId, version = entry.version)
            } else {
                document.alarms.firstOrNull { it.id == entry.alarmId }?.let { changes += Change(op = OutboxEntry.UPSERT, alarm = it) }
            }
            sent += entry
        }
        return changes to sent
    }

    fun encode(changes: List<Change>): String = AlarmRepository.JSON.encodeToString(kotlinx.serialization.builtins.ListSerializer(Change.serializer()), changes)

    fun decode(json: String): Response = AlarmRepository.JSON.decodeFromString(Response.serializer(), json)
}

/** Logging hook for the pure alarm module (the app routes it to PLog). */
object AlarmLog {
    @Volatile var sink: ((String) -> Unit)? = null
}
