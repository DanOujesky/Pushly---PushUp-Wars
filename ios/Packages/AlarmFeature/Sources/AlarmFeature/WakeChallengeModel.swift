import AlarmDomain
import Core
import Foundation
import Observation
import RepEngine
import WakeFlowFeature

/// Runs one wake challenge in the camera (doc 04 §3, PS-30…PS-34): applies the mode rules live, finishes the camera
/// session, decides the provisional result with `WakeRules` (same rules as the server) and queues the rep log.
/// The server's answer replaces the provisional result when it arrives (PS-90). Mirrors Android `WakeChallenge`.
@MainActor
@Observable
public final class WakeChallengeModel {
    public enum Phase: Equatable {
        /// Counting towards the target (ringUntilDone, beatTheClock, escalation) or a set (sets).
        case counting
        /// Sprint: waiting for the push-up position, then 3-2-1.
        case sprintReady
        case sprintCountdown(Int)
        case sprinting(endsAtMs: Int64)
        /// Sets: rest between sets; the next set must start before `startByMs` (rest + 30 s).
        case rest(endsAtMs: Int64, startByMs: Int64)
        case done
    }

    public let ring: RingState
    public let reps: RepSessionModel
    public let sessionId = UUID().uuidString.lowercased()
    public private(set) var phase: Phase = .counting
    public private(set) var decision: WakeRules.Decision?
    public private(set) var setIndex = 0
    /// Called once when the challenge is over (stop the alarm / nags). `succeeded` is the provisional result.
    public var onOver: ((_ succeeded: Bool) -> Void)?
    /// Rest is over: the app plays the alarm sound again until the next set starts (doc 04 §3 sets).
    public var onRestOver: (() -> Void)?

    private let services: SessionServices?
    private var anchor: ServerAnchor?
    private var sprintStartCount = 0
    private var setStartCount = 0
    private var setEndMs: Int64?
    private var ticker: Task<Void, Never>?

    public init(ring: RingState, services: SessionServices?, clock: any AppClock = SystemClock()) {
        self.ring = ring
        self.services = services
        let type = ring.mode.modeType ?? .ringUntilDone
        switch type {
        case .ringUntilDone, .escalation, .beatTheClock:
            reps = RepSessionModel(mode: .wake(target: max(ring.target, 1)), clock: clock) { _ in }
        case .sprint, .sets:
            reps = RepSessionModel(mode: .open, clock: clock) { _ in }
        }
        if type == .sprint { phase = .sprintReady }
        reps.onCounted = { [weak self] total in self?.counted(total) }
        refreshDisplay()
    }

    public var result: SessionResult? { services?.uploader.results[sessionId] }
    public var pending: Bool { services?.uploader.isPending(sessionId: sessionId) ?? false }

    /// Starts the clock work (sprint countdown, rest timers, deadline) and fetches the server anchor.
    public func start() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        Task { [weak self] in
            guard let self, let services else { return }
            anchor = await services.anchor()
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }

    public func giveUp() { finish(outcome: "gaveUp") }

    // MARK: Live rules

    private var nowMs: Int64 { Int64(reps.nowDate.timeIntervalSince1970 * 1000) }
    private var monoMs: Int64 { reps.monotonicNowMs }

    func tick() {
        guard phase != .done else { return }
        if reps.nowDate >= ring.deadline {
            finish(outcome: "expired")
            return
        }
        switch phase {
        case .sprintReady:
            if reps.state != .notReady {
                phase = .sprintCountdown(3)
                countdownStartedMs = monoMs
            }
        case .sprintCountdown:
            let left = 3 - Int((monoMs - countdownStartedMs) / 1000)
            if left <= 0 {
                reps.markSprintStart()
                sprintStartCount = reps.counted
                phase = .sprinting(endsAtMs: monoMs + Int64(ring.mode.windowSeconds ?? 60) * 1000)
            } else if phase != .sprintCountdown(left) {
                phase = .sprintCountdown(left)
            }
        case let .sprinting(endsAt):
            if monoMs >= endsAt { finish(outcome: "completed") }
        case let .rest(endsAt, startBy):
            if monoMs >= startBy {
                finish(outcome: "expired")     // next set not started in time (rest + 30 s)
                return
            }
            if monoMs >= endsAt, !restOverSignalled {
                restOverSignalled = true
                onRestOver?()
            }
        case .counting, .done:
            break
        }
        refreshDisplay()
    }

    private var countdownStartedMs: Int64 = 0
    private var restOverSignalled = false

    private var type: ModeType { ring.mode.modeType ?? .ringUntilDone }

    private func counted(_ total: Int) {
        switch type {
        case .ringUntilDone, .escalation, .beatTheClock:
            if total >= ring.target {
                finish(outcome: "completed")
                return
            }
        case .sets:
            if case .rest = phase {
                // First rep of the next set ends the rest.
                setIndex += 1
                setStartCount = total - 1
                phase = .counting
            }
            if total - setStartCount >= (ring.mode.repsPerSet ?? 1) {
                closeSet(total: total)
            }
        case .sprint:
            break
        }
        refreshDisplay()
    }

    /// The set's span runs from its first rep's start to its last rep's end (server rule: doc 04 §3 sets).
    private func closeSet(total: Int) {
        guard let timeline = reps.timeline else { return }
        let setReps = Array(timeline.reps.suffix(total - setStartCount))
        if let first = setReps.first, let last = setReps.last {
            reps.appendSet(startMs: first.tStartMs, endMs: last.tEndMs)
        }
        if setIndex + 1 >= (ring.mode.sets ?? 1) {
            finish(outcome: "completed")
            return
        }
        let rest = Int64(ring.mode.restSeconds ?? 0) * 1000
        restOverSignalled = false
        phase = .rest(endsAtMs: monoMs + rest, startByMs: monoMs + rest + WakeRules.setStartGraceSeconds * 1000)
    }

    private func refreshDisplay() {
        switch (type, phase) {
        case (.sprint, .sprintReady):
            reps.display = .init(value: "\(ring.mode.windowSeconds ?? 60) s",
                                 caption: String(localized: "Sprint — get into position"))
        case let (.sprint, .sprintCountdown(n)):
            reps.display = .init(value: "\(n)", caption: String(localized: "Get ready"))
        case let (.sprint, .sprinting(endsAt)):
            let left = max(0, Int((endsAt - monoMs + 999) / 1000))
            let done = reps.counted - sprintStartCount
            let minimum = ring.mode.minimumReps ?? 0
            reps.display = .init(value: "\(done)",
                                 caption: String(localized: "\(left) s left · minimum \(minimum)"),
                                 progress: Double(done) / Double(max(minimum, 1)))
        case let (.sets, .rest(endsAt, startBy)):
            let restLeft = max(0, Int((endsAt - monoMs + 999) / 1000))
            reps.display = restLeft > 0
                ? .init(value: "\(restLeft) s", caption: String(localized: "Rest — set \(setIndex + 2) of \(ring.mode.sets ?? 1) next"))
                : .init(value: "\(max(0, Int((startBy - monoMs) / 1000))) s",
                        caption: String(localized: "Start set \(setIndex + 2) now"))
        case (.sets, _):
            let inSet = reps.counted - setStartCount
            let per = ring.mode.repsPerSet ?? 1
            reps.display = .init(value: "\(min(inSet, per)) / \(per)",
                                 caption: String(localized: "Set \(setIndex + 1) of \(ring.mode.sets ?? 1)"),
                                 progress: Double(inSet) / Double(max(per, 1)))
        default:
            reps.display = nil
        }
    }

    // MARK: Finish

    private func finish(outcome: String) {
        guard phase != .done else { return }
        phase = .done
        stop()
        reps.finish(outcome: outcome)
        let session = provisionalSession()
        let d = WakeRules.decide(mode: ring.mode, t0: Int64(ring.t0Date.timeIntervalSince1970 * 1000), now: nowMs,
                                 session: session)
        // The camera session is over: anything not succeeded now is a failure for this attempt.
        decision = d.status == "in_progress" ? d.with(status: "failed") : d
        if let services {
            let practice = ring.practice || !ring.countsForChallenge
            services.uploader.enqueue(reps.repLog(
                sessionId: sessionId, context: practice ? "training" : "wake",
                occurrenceId: practice ? nil : ring.occurrenceId, snoozes: ring.snoozesUsed, anchor: anchor,
                ringAt: ring.rangAtDate, appVersion: services.appVersion))
        }
        onOver?(decision?.status == "succeeded")
    }

    /// The session in wall-clock epoch ms for the provisional decision (the server uses its own anchor).
    func provisionalSession() -> WakeRules.Session {
        guard let tl = reps.timeline else {
            return .init(startedAt: nowMs, endedAt: nowMs, ringAt: nil, outcome: reps.outcome, snoozes: 0, reps: [])
        }
        let base = Int64(tl.wallStart.timeIntervalSince1970 * 1000)
        return WakeRules.Session(
            startedAt: base, endedAt: base + ((tl.monotonicEndMs ?? tl.monotonicStartMs) - tl.monotonicStartMs),
            ringAt: Int64(ring.rangAtDate.timeIntervalSince1970 * 1000), outcome: reps.outcome,
            snoozes: ring.snoozesUsed,
            reps: tl.reps.map { .init(tStart: base + $0.tStartMs, tEnd: base + $0.tEndMs, quality: $0.quality) },
            sets: tl.sets.map { .init(start: base + $0.startMs, end: base + $0.endMs) },
            sprintStart: tl.sprintStartMs.map { base + $0 })
    }
}
