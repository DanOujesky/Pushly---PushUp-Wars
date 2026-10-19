package app.pushly.core.common

/** Injectable time source (doc 03 §3, roadmap P0-07). */
interface AppClock {
    /** Wall clock, epoch milliseconds. */
    fun nowMs(): Long

    /** Monotonic milliseconds, unaffected by the user changing the device clock (doc 06 §3). */
    fun monotonicMs(): Long
}

/** JVM implementation. On Android, the app module provides one based on SystemClock.elapsedRealtime(). */
object JvmClock : AppClock {
    override fun nowMs(): Long = System.currentTimeMillis()
    override fun monotonicMs(): Long = System.nanoTime() / 1_000_000
}

/** Manually advanced clock for tests. */
class FixedClock(private var now: Long, private var monotonic: Long = 0) : AppClock {
    override fun nowMs(): Long = now
    override fun monotonicMs(): Long = monotonic

    fun advance(ms: Long) {
        now += ms
        monotonic += ms
    }
}
