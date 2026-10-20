import Foundation
import WakeFlowFeature

/// `get_wake_summary()` (shared/contracts/wake-summary.schema.json): today's challenge, streak and recent days.
public struct WakeSummary: Codable, Hashable, Sendable {
    public struct Plan: Codable, Hashable, Sendable {
        /// ring | paused | skipped | none
        public var kind: String
        public var occurrenceId: String?
        public var t0: String?
        public var deadline: String?
    }

    public struct Attempt: Codable, Hashable, Sendable {
        public var localDate: String
        public var status: String
        public var points: Int
        public var reason: String?
        public var finalTargetReps: Int?
        public var score: Int?
    }

    public var today: String
    public var plan: Plan
    public var streak: SessionResult.Streak
    public var attempts: [Attempt]
    public var repsToday: Int?

    /// Status per local date (YYYY-MM-DD) for the week strip.
    public func status(on date: String) -> String? { attempts.first { $0.localDate == date }?.status }
}
