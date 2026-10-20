package app.pushly.feature.alarm

import android.content.Context
import android.util.AtomicFile
import app.pushly.core.alarm.AlarmRepository
import app.pushly.core.alarm.DocumentStore
import java.io.File
import java.io.FileNotFoundException

/**
 * Process-wide alarm components. Receivers, the ring service and the UI all share one repository and one scheduler.
 * (A plain holder until Hilt arrives — P0-03.) Data lives in device-protected storage so alarms can be re-armed
 * after a reboot before the user unlocks (doc 04 §6.2, direct boot).
 */
class AlarmSystem private constructor(context: Context) {
    val appContext: Context = context.applicationContext
    private val deviceContext: Context = appContext.createDeviceProtectedStorageContext()
    val repository = AlarmRepository(FileDocumentStore(File(deviceContext.filesDir, "alarms.json")))
    val scheduler = AlarmScheduler(appContext, deviceContext, repository)
    val sync = AlarmSyncCoordinator(repository)

    companion object {
        @Volatile private var instance: AlarmSystem? = null

        fun get(context: Context): AlarmSystem = instance ?: synchronized(this) {
            instance ?: AlarmSystem(context).also { instance = it }
        }
    }
}

/** Atomic JSON file (write to temp + rename), so a crash mid-write never loses the alarms. */
class FileDocumentStore(file: File) : DocumentStore {
    private val atomic = AtomicFile(file)

    override fun read(): String? = try {
        atomic.readFully().decodeToString()
    } catch (_: FileNotFoundException) {
        null
    }

    override fun write(content: String) {
        val out = atomic.startWrite()
        try {
            out.write(content.encodeToByteArray())
            atomic.finishWrite(out)
        } catch (e: java.io.IOException) {
            atomic.failWrite(out)
            throw e
        }
    }
}
