import Core
import DesignSystem
import RepEngine
import SwiftUI

/// Drives one workout (D-069): the camera counts, `WorkoutRunner` turns push-ups into sets and rest, this class
/// turns runner events into cues, set markers for the rep log and the counter display.
@MainActor
@Observable
public final class WorkoutSessionModel {
    public let workout: Workout
    public let reps: RepSessionModel
    public private(set) var runner: WorkoutRunner
    public private(set) var completed = false
    @ObservationIgnored private var seen = 0
    @ObservationIgnored private var lastBeep: Int64 = -1
    @ObservationIgnored private let sounds = RepSounds()
    @ObservationIgnored private let onComplete: () -> Void

    public init(workout: Workout, reps: RepSessionModel? = nil, onComplete: @escaping () -> Void = {}) {
        self.workout = workout
        // The count is spoken per set here ("1", "2", … of this set), not the session total.
        self.reps = reps ?? RepSessionModel(mode: .training, speakCount: false) { _ in }
        self.runner = WorkoutRunner(workout: workout)
        self.onComplete = onComplete
        self.reps.onCounted = { [weak self] total in self?.counted(total) }
        refreshDisplay()
    }

    private var now: Int64 { reps.monotonicNowMs }

    /// Sets start once the user is in position (the camera sees a plank) — not while the phone is being propped up.
    public func stateChanged(_ state: RepState) {
        if state != .notReady, runner.phase == .ready { step { $0.start(now) } }
    }

    public func tick() { step { $0.tick(now) } }
    public func endSet() { step { $0.endSet(now) } }
    public func skipRest() { step { $0.skipRest(now) } }
    public func finish() { step { $0.finish(now) } }

    private func counted(_ total: Int) {
        while seen < total {
            seen += 1
            step { $0.rep(now) }
            // the last rep of a set is followed by the rest call instead
            if runner.phase == .set, runner.setReps > 0 { sounds.say("\(runner.setReps)") }
        }
    }

    private func step(_ change: (inout WorkoutRunner) -> Void) {
        guard !completed else { return }
        let before = runner.events.count
        change(&runner)
        for event in runner.events.dropFirst(before) { react(event) }
        if runner.phase == .rest { restBeeps() }
        refreshDisplay()
    }

    private func react(_ event: WorkoutRunner.Event) {
        switch event {
        case let .setStarted(set, _):
            reps.markSetStart()
            sounds.play(.go)
            sounds.announce(WorkoutText.setCall(set + 1, of: workout.sets.count, set: workout.sets[set]))
        case .setEnded:
            reps.markSetEnd()
            sounds.play(.done)
        case let .restStarted(_, until, t):
            sounds.announce(WorkoutText.restCall(seconds: Int((until - t + 999) / 1000)))
        case .done:
            completed = true
            reps.finish()
            onComplete()
        }
    }

    private func restBeeps() {
        guard let left = runner.snapshot(now).msLeft else { return }
        let second = (left + 999) / 1000
        if (1...3).contains(second), second != lastBeep {
            lastBeep = second
            sounds.play(.count)
        }
    }

    private func refreshDisplay() {
        let snap = runner.snapshot(now)
        let count = workout.sets.count
        switch snap.phase {
        case .ready:
            reps.display = .init(value: "0", caption: String(localized: "Get into a plank to start set 1"), progress: nil)
        case .set:
            let s = runner.currentSet
            var caption = String(localized: "Set \(snap.index + 1) of \(count)")
            var progress: Double?
            switch s.kind {
            case .reps:
                caption += " · " + String(localized: "goal \(s.target)")
                progress = Double(snap.setReps) / Double(max(s.target, 1))
            case .timed:
                progress = snap.msLeft.map { 1 - Double($0) / Double(max(s.target, 1) * 1000) }
            case .amrap:
                caption += " · " + String(localized: "as many as you can")
            }
            if let left = snap.msLeft { caption += " · " + WorkoutText.clock(left) }
            reps.display = .init(value: "\(snap.setReps)", caption: caption, progress: progress)
        case .rest:
            let next = workout.sets[min(snap.index, count - 1)]
            reps.display = .init(value: WorkoutText.clock(snap.msLeft ?? 0),
                                 caption: String(localized: "Rest · next: \(WorkoutText.setLabel(next))"), progress: nil)
        case .done:
            reps.display = .init(value: "\(snap.total)", caption: String(localized: "Workout done"), progress: 1)
        }
    }
}

/// The workout screen: camera + counter (`RepSessionView`) with set / rest controls, then the summary. The whole
/// workout is one training session — every push-up counts for the day (stats, leaderboards, Clan Wars; side view).
public struct WorkoutRunView: View {
    let services: SessionServices?
    let onClose: () -> Void
    @State private var session: WorkoutSessionModel
    @State private var done = false
    @State private var anchor: ServerAnchor?
    @State private var sessionId: String?

    public init(workout: Workout, services: SessionServices? = nil, onClose: @escaping () -> Void) {
        self.services = services
        self.onClose = onClose
        _session = State(initialValue: WorkoutSessionModel(workout: workout))
    }

    public var body: some View {
        if done {
            TrainingSummaryView(summary: session.reps.summary,
                                result: sessionId.flatMap { services?.uploader.results[$0] },
                                pending: sessionId.map { services?.uploader.isPending(sessionId: $0) ?? false } ?? false,
                                workout: session.workout, sets: session.runner.results,
                                frontReps: session.reps.frontReps, onDone: onClose)
        } else {
            RepSessionView(model: session.reps) { footer }
                .onChange(of: session.reps.state) { _, state in session.stateChanged(state) }
                .onChange(of: session.completed) { _, completed in if completed { submit() } }
                .task { anchor = await services?.anchor() }
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(200))
                        session.tick()
                    }
                }
        }
    }

    private var footer: some View {
        HStack(spacing: SpacingTokens.s) {
            switch session.runner.phase {
            case .set where session.workout.everyS == nil && session.runner.currentSet.kind != .timed:
                GhostButton("End set") { session.endSet() }
            case .rest where session.workout.everyS == nil:
                GhostButton("Skip rest") { session.skipRest() }
            default:
                EmptyView()
            }
            Spacer()
            if session.runner.phase == .ready && session.reps.counted == 0 {
                PrimaryButton("Close") {
                    session.reps.stop()
                    onClose()
                }
                .frame(maxWidth: 160)
            } else {
                PrimaryButton("Finish") { session.finish() }
                    .frame(maxWidth: 160)
            }
        }
    }

    private func submit() {
        if session.reps.counted > 0, let services { sessionId = services.submitTraining(session.reps, anchor: anchor) }
        done = true
    }
}

/// Copy shared by the workout screens (String Catalog; Android strings.xml has the same English).
public enum WorkoutText {
    public static func clock(_ ms: Int64) -> String {
        let s = Int((ms + 999) / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    public static func setLabel(_ s: WorkoutSet) -> String {
        switch s.kind {
        case .reps: String(localized: "\(s.target) push-ups")
        case .amrap: String(localized: "max push-ups")
        case .timed: String(localized: "\(s.target) s all-out")
        }
    }

    static func setCall(_ n: Int, of total: Int, set: WorkoutSet) -> String {
        n == total ? String(localized: "Last set. \(setLabel(set)). Go!") : String(localized: "Set \(n). \(setLabel(set)). Go!")
    }

    static func restCall(seconds: Int) -> String { String(localized: "Rest \(seconds) seconds") }

    /// "5 sets · 75 push-ups · ~8 min" for compact cards.
    public static func summary(_ w: Workout) -> String {
        let sets = String(localized: "\(w.sets.count) sets")
        let reps = w.plannedReps.map { String(localized: "\($0) push-ups") }
        return ([sets] + (reps.map { [$0] } ?? []) + [duration(w.estimatedSeconds)]).joined(separator: " · ")
    }

    public static func duration(_ seconds: Int) -> String {
        seconds < 60 ? String(localized: "\(seconds) s") : String(localized: "~\(max(1, (seconds + 30) / 60)) min")
    }
}
