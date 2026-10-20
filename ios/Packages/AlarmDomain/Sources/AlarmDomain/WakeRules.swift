import Foundation

/// Wake Challenge decision rules (doc 04 §3, doc 08 §3) — the app's provisional copy of what the server decides.
/// Port of tools/reference/pushly_ref/wake.py; tested against shared/test-vectors/wake (same as Android + SQL).
/// All times are epoch milliseconds.
public enum WakeRules {
    public static let deadlineMs: Int64 = 30 * 60_000
    public static let clockToleranceMs: Int64 = 30_000
    public static let setStartGraceSeconds: Int64 = 30

    public struct Rep: Codable, Hashable, Sendable {
        public var tStart: Int64
        public var tEnd: Int64
        public var quality: Int

        public init(tStart: Int64, tEnd: Int64, quality: Int) {
            self.tStart = tStart
            self.tEnd = tEnd
            self.quality = quality
        }
    }

    public struct SetSpan: Codable, Hashable, Sendable {
        public var start: Int64
        public var end: Int64

        public init(start: Int64, end: Int64) {
            self.start = start
            self.end = end
        }
    }

    public struct Session: Codable, Hashable, Sendable {
        public var startedAt: Int64
        public var endedAt: Int64
        public var ringAt: Int64?
        /// completed | gaveUp | expired
        public var outcome: String
        public var snoozes: Int
        public var reps: [Rep]
        public var sets: [SetSpan]
        public var sprintStart: Int64?

        public init(startedAt: Int64, endedAt: Int64, ringAt: Int64?, outcome: String, snoozes: Int, reps: [Rep],
                    sets: [SetSpan] = [], sprintStart: Int64? = nil) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.ringAt = ringAt
            self.outcome = outcome
            self.snoozes = snoozes
            self.reps = reps
            self.sets = sets
            self.sprintStart = sprintStart
        }

        enum CodingKeys: String, CodingKey { case startedAt, endedAt, ringAt, outcome, snoozes, reps, sets, sprintStart }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            startedAt = try c.decode(Int64.self, forKey: .startedAt)
            endedAt = try c.decode(Int64.self, forKey: .endedAt)
            ringAt = try c.decodeIfPresent(Int64.self, forKey: .ringAt)
            outcome = try c.decodeIfPresent(String.self, forKey: .outcome) ?? "completed"
            snoozes = try c.decodeIfPresent(Int.self, forKey: .snoozes) ?? 0
            reps = try c.decodeIfPresent([Rep].self, forKey: .reps) ?? []
            sets = try c.decodeIfPresent([SetSpan].self, forKey: .sets) ?? []
            sprintStart = try c.decodeIfPresent(Int64.self, forKey: .sprintStart)
        }
    }

    public struct Decision: Codable, Hashable, Sendable {
        /// succeeded | in_progress | failed | missed
        public var status: String
        public var finalTargetReps: Int
        public var successAt: Int64?
        public var score: Int
        public var reason: String
        public var snoozesUsed: Int

        public init(status: String, finalTargetReps: Int, successAt: Int64?, score: Int, reason: String, snoozesUsed: Int) {
            self.status = status
            self.finalTargetReps = finalTargetReps
            self.successAt = successAt
            self.score = score
            self.reason = reason
            self.snoozesUsed = snoozesUsed
        }

        /// The same decision with another status.
        public func with(status: String) -> Decision {
            var copy = self
            copy.status = status
            return copy
        }
    }

    public static func finalTarget(_ mode: ChallengeMode, snoozes: Int) -> Int {
        switch mode.modeType {
        case .sprint: mode.minimumReps ?? 0
        case .sets: (mode.sets ?? 0) * (mode.repsPerSet ?? 0)
        case .escalation: (mode.targetReps ?? 0) + min(snoozes, mode.maxSnoozes ?? 0) * (mode.snoozeAddsReps ?? 0)
        default: mode.targetReps ?? 0
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public static func decide(mode: ChallengeMode, t0: Int64, now: Int64, session s: Session) -> Decision {
        let deadline = t0 + deadlineMs
        let type = mode.modeType
        let snoozes = type == .escalation ? min(s.snoozes, mode.maxSnoozes ?? 0) : 0
        let target = finalTarget(mode, snoozes: snoozes)
        let reps = s.reps.filter { $0.tStart >= t0 - clockToleranceMs && $0.tEnd <= deadline }
            .sorted { ($0.tEnd, $0.tStart) < ($1.tEnd, $1.tStart) }
        var successAt: Int64?
        var score = reps.count
        var reason = "not_reached"

        if s.startedAt > deadline {
            reason = "started_after_deadline"
        } else {
            switch type {
            case .ringUntilDone, .escalation, .none:
                if target > 0, reps.count >= target { successAt = reps[target - 1].tEnd }
            case .beatTheClock:
                let start = s.ringAt.map { max(t0, min($0, deadline)) } ?? t0
                let inside = reps.filter { $0.tEnd <= start + Int64(mode.windowSeconds ?? 0) * 1000 }
                score = inside.count
                if target > 0, inside.count >= target {
                    successAt = inside[target - 1].tEnd
                } else if reps.count >= target {
                    reason = "window_expired"
                }
            case .sprint:
                if let start = s.sprintStart {
                    if start > deadline || start < t0 - clockToleranceMs {
                        reason = "sprint_outside_deadline"
                    } else {
                        let end = start + Int64(mode.windowSeconds ?? 0) * 1000
                        let inside = reps.filter { $0.tStart >= start && $0.tEnd <= end }
                        score = inside.count
                        let minimum = mode.minimumReps ?? 0
                        if minimum > 0, inside.count >= minimum {
                            successAt = inside[minimum - 1].tEnd
                        } else if s.endedAt >= end || now >= end {
                            reason = "sprint_too_few"
                        }
                    }
                } else {
                    reason = "sprint_not_started"
                }
            case .sets:
                var done = 0
                var prevEnd: Int64?
                let rest = Int64(mode.restSeconds ?? 0)
                for set in s.sets.sorted(by: { $0.start < $1.start }) {
                    if let p = prevEnd, set.start > p + (rest + setStartGraceSeconds) * 1000 {
                        reason = "rest_too_long"
                        break
                    }
                    let n = reps.filter { $0.tStart >= set.start && $0.tEnd <= set.end }.count
                    if n < (mode.repsPerSet ?? 0) { break }
                    done += 1
                    prevEnd = set.end
                    if done == (mode.sets ?? 0) {
                        successAt = set.end
                        break
                    }
                }
                score = done
            }
        }

        var status: String
        if successAt != nil {
            status = "succeeded"
            reason = "ok"
        } else if s.outcome == "gaveUp" || now > deadline
            || ["window_expired", "sprint_too_few", "rest_too_long", "sprint_outside_deadline"].contains(reason) {
            status = "failed"
        } else {
            status = "in_progress"
        }
        if reason == "started_after_deadline" { status = "missed" }
        return Decision(status: status, finalTargetReps: target, successAt: successAt, score: score, reason: reason,
                        snoozesUsed: snoozes)
    }

    /// Wake Score of a succeeded attempt (doc 08 §3, integer math).
    public static func points(finalTargetReps: Int, mode: String, snoozesUsed: Int, avgQuality: Int) -> Int {
        let difficulty = min(20, finalTargetReps / 5)
        let bonus = switch ModeType(rawValue: mode) {
        case .beatTheClock, .sprint, .sets: 3
        case .escalation: -2 * snoozesUsed
        default: 0
        }
        let quality = avgQuality >= 90 ? 3 : (avgQuality >= 75 ? 1 : 0)
        return max(5, 10 + difficulty + bonus + quality)
    }
}
