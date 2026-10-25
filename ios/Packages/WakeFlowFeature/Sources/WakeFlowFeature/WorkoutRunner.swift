import Foundation

/// Workout runner (D-069) — port of tools/reference/pushly_ref/workout.py; replays
/// shared/test-vectors/workouts/runner.json. Times are monotonic milliseconds.
public struct WorkoutRunner: Sendable {
    public enum Phase: String, Sendable { case ready, set, rest, done }

    public enum Event: Equatable, Sendable {
        case setStarted(set: Int, t: Int64)
        case setEnded(set: Int, reps: Int, completed: Bool, t: Int64)
        case restStarted(next: Int, until: Int64, t: Int64)
        case done(t: Int64)
    }

    public struct SetResult: Equatable, Sendable {
        public let reps: Int
        public let target: Int
        public let completed: Bool
    }

    public struct Snapshot: Equatable, Sendable {
        public let phase: Phase
        public let index: Int
        public let setReps: Int
        public let total: Int
        public let msLeft: Int64?
    }

    public let workout: Workout
    public private(set) var phase: Phase = .ready
    /// Current set (in rest: the set that comes next).
    public private(set) var index = 0
    public private(set) var setReps = 0
    public private(set) var total = 0
    public private(set) var results: [SetResult] = []
    public private(set) var events: [Event] = []
    private var setStart: Int64 = 0
    private var restEnd: Int64 = 0

    public init(workout: Workout) { self.workout = workout }

    private var sets: [WorkoutSet] { workout.sets }
    private var everyMs: Int64? { workout.everyS.flatMap { $0 > 0 ? Int64($0) * 1000 : nil } }
    public var currentSet: WorkoutSet { sets[min(index, sets.count - 1)] }

    // MARK: inputs

    public mutating func start(_ t: Int64) {
        if phase == .ready { startSet(0, t) }
    }

    public mutating func rep(_ t: Int64) {
        tick(t)
        guard phase == .set || phase == .rest else { return }
        total += 1
        guard phase == .set else { return }
        setReps += 1
        let s = sets[index]
        if s.kind == .reps, setReps >= s.target { endCurrent(t) }
    }

    public mutating func tick(_ t: Int64) {
        while true {
            switch phase {
            case .set:
                guard let d = setDeadline(), t >= d else { return }
                endCurrent(d)
            case .rest:
                guard t >= restEnd else { return }
                startSet(index, restEnd)
            case .ready, .done:
                return
            }
        }
    }

    public mutating func endSet(_ t: Int64) {
        tick(t)
        if phase == .set { endCurrent(t) }
    }

    public mutating func skipRest(_ t: Int64) {
        tick(t)
        if phase == .rest { startSet(index, t) }
    }

    /// The user stops early: a running set is recorded as it is, the rest are skipped.
    public mutating func finish(_ t: Int64) {
        tick(t)
        if phase == .set { record(t) }
        if phase != .done {
            phase = .done
            events.append(.done(t: t))
        }
    }

    public func snapshot(_ t: Int64) -> Snapshot {
        var left: Int64?
        if phase == .set {
            if let d = setDeadline(), currentSet.kind != .amrap { left = max(d - t, 0) }
        } else if phase == .rest {
            left = max(restEnd - t, 0)
        }
        return Snapshot(phase: phase, index: index, setReps: setReps, total: total, msLeft: left)
    }

    // MARK: internals

    private func setDeadline() -> Int64? {
        let s = sets[index]
        if let everyMs { return setStart + everyMs }
        if s.kind == .timed { return setStart + Int64(s.target) * 1000 }
        return nil
    }

    private mutating func startSet(_ i: Int, _ t: Int64) {
        phase = .set
        index = i
        setReps = 0
        setStart = t
        events.append(.setStarted(set: i, t: t))
    }

    private mutating func record(_ t: Int64) {
        let s = sets[index]
        let done = s.kind == .reps ? setReps >= s.target : setReps >= 1
        results.append(SetResult(reps: setReps, target: s.target, completed: done))
        events.append(.setEnded(set: index, reps: setReps, completed: done, t: t))
    }

    private mutating func endCurrent(_ t: Int64) {
        record(t)
        let next = index + 1
        guard next < sets.count else {
            phase = .done
            events.append(.done(t: t))
            return
        }
        let end = everyMs.map { setStart + $0 } ?? t + Int64(sets[index].restS) * 1000
        if end <= t {
            startSet(next, t)
            return
        }
        phase = .rest
        index = next
        restEnd = end
        events.append(.restStarted(next: next, until: end, t: t))
    }
}
