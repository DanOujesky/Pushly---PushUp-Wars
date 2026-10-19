import Foundation

/// Injectable time source (doc 03 §3, roadmap P0-07). Production code never calls `Date()` directly
/// in logic that needs testing (alarms, wake windows, rep timing).
public protocol AppClock: Sendable {
    /// Wall-clock time.
    func now() -> Date
    /// Monotonic milliseconds (not affected by the user changing the device clock — doc 06 §3).
    func monotonicMs() -> Int64
}

public struct SystemClock: AppClock {
    public init() {}

    public func now() -> Date { Date() }

    public func monotonicMs() -> Int64 {
        Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1_000_000)
    }
}

/// Test clock with manually advanced time.
public final class FixedClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var monotonic: Int64

    public init(now: Date, monotonicMs: Int64 = 0) {
        self.current = now
        self.monotonic = monotonicMs
    }

    public func now() -> Date { lock.withLock { current } }

    public func monotonicMs() -> Int64 { lock.withLock { monotonic } }

    public func advance(byMs ms: Int64) {
        lock.withLock {
            current = current.addingTimeInterval(Double(ms) / 1000)
            monotonic += ms
        }
    }
}
