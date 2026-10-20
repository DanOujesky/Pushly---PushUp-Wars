package app.pushly.feature.wakeflow

import app.pushly.core.common.AppClock
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.JvmClock
import app.pushly.core.common.PLog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import kotlin.math.min
import kotlin.math.pow

/** Server answer to a rep session (shared/contracts/submit-rep-session.response.schema.json). */
@Serializable
data class SessionResult(
    val sessionId: String,
    val verified: Boolean,
    val late: Boolean,
    val repsCounted: Int,
    val avgQuality: Int? = null,
    val wake: Wake? = null,
    val streak: Streak,
    val totals: Totals,
) {
    @Serializable data class Wake(
        val occurrenceId: String? = null,
        val status: String,
        val reason: String? = null,
        val points: Int? = null,
        val finalTargetReps: Int? = null,
        val score: Int? = null,
        val deadline: String? = null,
    )

    @Serializable data class Streak(
        val current: Int,
        val best: Int,
        val pureCurrent: Int,
        val pureBest: Int,
        val freezesAvailable: Int,
        val lastCountedDate: String? = null,
    )

    @Serializable data class Totals(val repsToday: Int? = null, val repsAllTime: Int? = null)

    companion object {
        fun decode(json: String): SessionResult = RepLog.JSON.decodeFromString(serializer(), json)
    }
}

/**
 * Outbox for rep logs (doc 03 §5, roadmap P4-05): every finished session is written to disk first, then uploaded when
 * signed in and online. Retries with backoff (5 s → 15 min) while the error is retryable; logs the server refuses for
 * good are dropped. Results are kept so screens can show validated values (PS-90). Same behaviour as iOS.
 */
class SessionUploader(
    private val directory: File,
    private val scope: CoroutineScope,
    private val sleep: suspend (Long) -> Unit = { delay(it) },
) {
    /** Returns the transport while signed in, null otherwise (set by the app). */
    @Volatile var transport: (suspend () -> (suspend (String) -> String)?)? = null

    private val queueDir = File(directory, "queue").apply { mkdirs() }
    private val resultsFile = File(directory, "results.json")
    private val mutex = Mutex()
    private var attempts = 0

    private val _pending = MutableStateFlow(queued().map { it.nameWithoutExtension }.toSet())
    val pending: StateFlow<Set<String>> = _pending.asStateFlow()
    private val _results = MutableStateFlow(loadResults())
    val results: StateFlow<Map<String, SessionResult>> = _results.asStateFlow()

    private fun queued(): List<File> = queueDir.listFiles { f -> f.extension == "json" }.orEmpty().sortedBy { it.name }

    fun isPending(sessionId: String): Boolean = _pending.value.any { it.endsWith(sessionId) }

    /** Persists the log and starts an upload attempt. */
    fun enqueue(log: RepLog, nowMs: Long = System.currentTimeMillis()) {
        try {
            val name = "$nowMs-${log.sessionId}"
            val tmp = File(queueDir, "$name.tmp")
            tmp.writeText(log.encode())
            tmp.renameTo(File(queueDir, "$name.json"))
            _pending.value = _pending.value + name
        } catch (e: java.io.IOException) {
            PLog.error(PLog.Category.Sync) { "Could not store rep log: ${e.message}" }
        }
        scope.launch { flush() }
    }

    /** Uploads everything queued, oldest first. Stops at the first retryable failure and retries later. */
    suspend fun flush() {
        if (mutex.isLocked) return
        mutex.withLock {
            while (true) {
                val file = queued().firstOrNull() ?: return
                val send = transport?.invoke() ?: return // signed out / guest: keep the queue
                try {
                    store(SessionResult.decode(send(file.readText())))
                    remove(file)
                    attempts = 0
                } catch (e: CancellationException) {
                    throw e
                } catch (e: AppError) {
                    if (!e.retryable && e.code != AppErrorCode.Unauthenticated) {
                        PLog.warning(PLog.Category.Sync) { "Rep log dropped by the server (${e.code.wire}): ${file.name}" }
                        remove(file)
                    } else {
                        retryLater()
                        return
                    }
                } catch (_: SerializationException) {
                    PLog.error(PLog.Category.Sync) { "Unreadable server answer for ${file.name}" }
                    remove(file)
                } catch (_: Exception) {
                    retryLater()
                    return
                }
            }
        }
    }

    private fun retryLater() {
        attempts++
        val delayMs = min(5_000.0 * 3.0.pow(attempts - 1), 900_000.0).toLong()
        PLog.warning(PLog.Category.Sync) { "Rep log upload failed, retry in ${delayMs / 1000} s" }
        scope.launch {
            sleep(delayMs)
            flush()
        }
    }

    private fun remove(file: File) {
        file.delete()
        _pending.value = _pending.value - file.nameWithoutExtension
    }

    private fun store(result: SessionResult) {
        val all = (_results.value + (result.sessionId to result)).entries.toList().takeLast(50).associate { it.key to it.value }
        _results.value = all
        try {
            resultsFile.writeText(RepLog.JSON.encodeToString(RESULTS, all))
        } catch (e: java.io.IOException) {
            PLog.warning(PLog.Category.Sync) { "Could not save results: ${e.message}" }
        }
    }

    private fun loadResults(): Map<String, SessionResult> = try {
        if (resultsFile.exists()) RepLog.JSON.decodeFromString(RESULTS, resultsFile.readText()) else emptyMap()
    } catch (_: SerializationException) {
        emptyMap()
    } catch (_: java.io.IOException) {
        emptyMap()
    }

    private companion object {
        val RESULTS = MapSerializer(String.serializer(), SessionResult.serializer())
    }
}

/**
 * What camera sessions need from the backend: the rep-log outbox, the server clock anchor and the app version.
 * Without a backend (guest builds) sessions still work and are queued, nothing is uploaded.
 */
class SessionServices(
    val uploader: SessionUploader,
    val appVersion: String,
    private val clock: AppClock = JvmClock,
) {
    /** Set by the app: server epoch ms from the `health` function. */
    @Volatile var fetchServerMs: (suspend () -> Long)? = null

    /** Set by the app: `get_wake_summary` JSON. */
    @Volatile var summary: (suspend () -> String)? = null

    /** Server clock anchor, at most 3 s of waiting; null offline (the server then checks the wall clock, D-044). */
    suspend fun anchor(): ServerAnchor? {
        val fetch = fetchServerMs ?: return null
        return try {
            withTimeoutOrNull(3_000) { ServerAnchor.measure(clock::monotonicMs, fetch) }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    /** Queues a finished free-training session (counts for totals, never for the wake streak). */
    fun submitTraining(model: RepSessionModel, anchor: ServerAnchor?): String {
        val id = java.util.UUID.randomUUID().toString()
        uploader.enqueue(model.repLog(id, "training", appVersion, anchor = anchor))
        return id
    }

    companion object {
        /** App-wide instance, set by the app module (a plain holder until Hilt arrives — P0-03). */
        @Volatile var shared: SessionServices? = null
    }
}
