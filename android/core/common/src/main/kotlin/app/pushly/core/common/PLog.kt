package app.pushly.core.common

/**
 * The only logging entry point (CLAUDE.md §4.6 — no Log.d / println in production paths).
 * Pure Kotlin: the app installs an Android sink at startup (`PLog.sink = AndroidLogSink`).
 */
object PLog {
    enum class Category { App, Alarm, Camera, Pose, Rep, Sync, Battle, Clan, Ads, Purchases }
    enum class Level { Debug, Info, Warning, Error }

    fun interface Sink {
        fun log(level: Level, category: Category, message: String)
    }

    @Volatile
    var sink: Sink = Sink { _, _, _ -> }

    @Volatile
    var debugEnabled: Boolean = false

    fun debug(category: Category = Category.App, message: () -> String) {
        if (debugEnabled) sink.log(Level.Debug, category, message())
    }

    fun info(category: Category = Category.App, message: () -> String) = sink.log(Level.Info, category, message())

    fun warning(category: Category = Category.App, message: () -> String) = sink.log(Level.Warning, category, message())

    fun error(category: Category = Category.App, message: () -> String) = sink.log(Level.Error, category, message())
}
