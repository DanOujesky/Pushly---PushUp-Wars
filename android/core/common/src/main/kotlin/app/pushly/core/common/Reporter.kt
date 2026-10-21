package app.pushly.core.common

/** What a report is about (`report(target, reason)` RPC). Same as iOS `ReportTarget`. */
sealed interface ReportTarget {
    data class User(val id: String) : ReportTarget
    data class Battle(val id: String) : ReportTarget
    data class Message(val id: Long) : ReportTarget
    data class Clan(val id: String) : ReportTarget

    val json: Map<String, String>
        get() = when (this) {
            is User -> mapOf("userId" to id)
            is Battle -> mapOf("battleId" to id)
            is Message -> mapOf("messageId" to id.toString())
            is Clan -> mapOf("clanId" to id)
        }
}

/**
 * Report anything another user did (doc 06 §6, doc 16 §5, store UGC rules): features call `Reporter.send(...)`; the app
 * installs the backend call. Returns true when stored; without a handler (guest / no backend) reporting is unavailable.
 */
object Reporter {
    @Volatile var handler: (suspend (ReportTarget, String) -> Boolean)? = null

    val isAvailable: Boolean get() = handler != null

    suspend fun send(target: ReportTarget, reason: String): Boolean = handler?.invoke(target, reason) ?: false
}
