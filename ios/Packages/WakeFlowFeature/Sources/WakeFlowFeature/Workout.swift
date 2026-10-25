import Foundation

/// A workout plan (D-069, contract shared/contracts/workout.schema.json). Built-in presets are generated from
/// shared/workouts/presets.json; the user's own workouts are stored on the device (`WorkoutStore`).
public struct Workout: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    /// EMOM: every set starts `everyS` seconds after the previous one (restS is ignored).
    public var everyS: Int?
    public var isPreset: Bool
    public var sets: [WorkoutSet]

    public init(id: String = UUID().uuidString, name: String, description: String = "", everyS: Int? = nil,
                isPreset: Bool = false, sets: [WorkoutSet]) {
        self.id = id
        self.name = name
        self.description = description
        self.everyS = everyS
        self.isPreset = isPreset
        self.sets = sets
    }

    enum CodingKeys: String, CodingKey { case id, name, description, everyS, sets }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        everyS = try c.decodeIfPresent(Int.self, forKey: .everyS)
        isPreset = false
        sets = try c.decode([WorkoutSet].self, forKey: .sets)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        if !description.isEmpty { try c.encode(description, forKey: .description) }
        try c.encodeIfPresent(everyS, forKey: .everyS)
        try c.encode(sets, forKey: .sets)
    }

    /// Push-ups the plan asks for, or nil when a set has no fixed count (AMRAP / timed).
    public var plannedReps: Int? {
        var total = 0
        for s in sets {
            guard s.kind == .reps else { return nil }
            total += s.target
        }
        return total
    }

    /// Rough length in seconds (reps sets assume 2 s per push-up), for the list.
    public var estimatedSeconds: Int {
        if let everyS { return everyS * sets.count }
        var t = 0
        for (i, s) in sets.enumerated() {
            switch s.kind {
            case .reps: t += s.target * 2
            case .timed: t += s.target
            case .amrap: t += 45
            }
            if i < sets.count - 1 { t += s.restS }
        }
        return t
    }

    // Limits (tools/reference/pushly_ref/workout.py).
    public static let maxSets = 20
    public static let maxTargetReps = 200
    public static let timedRange = 5...600
    public static let maxRestS = 600
    public static let everyRange = 20...300

    /// Problems that keep a user-made workout from being saved (empty = valid). Same codes as the reference.
    public var validationErrors: [String] {
        var errs: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errs.append("name") }
        if sets.isEmpty || sets.count > Self.maxSets { errs.append("sets") }
        if let everyS, !Self.everyRange.contains(everyS) { errs.append("everyS") }
        for (i, s) in sets.enumerated() {
            switch s.kind {
            case .reps where !(1...Self.maxTargetReps).contains(s.target): errs.append("sets[\(i)].target")
            case .timed where !Self.timedRange.contains(s.target): errs.append("sets[\(i)].target")
            case .amrap where s.target != 0: errs.append("sets[\(i)].target")
            default: break
            }
            if everyS != nil, s.kind != .reps { errs.append("sets[\(i)].kind") }
            if !(0...Self.maxRestS).contains(s.restS) { errs.append("sets[\(i)].restS") }
        }
        return errs
    }
}

public enum SetKind: String, Codable, CaseIterable, Sendable {
    /// Ends when `target` push-ups are done.
    case reps
    /// As many as possible: ends only when the user taps End set.
    case amrap
    /// Ends after `target` seconds.
    case timed
}

public struct WorkoutSet: Codable, Equatable, Sendable {
    public var kind: SetKind
    /// reps: push-ups; timed: seconds; amrap: 0.
    public var target: Int
    /// Rest after this set, seconds.
    public var restS: Int

    public init(kind: SetKind, target: Int, restS: Int) {
        self.kind = kind
        self.target = target
        self.restS = restS
    }
}

/// The user's own workouts, kept on the device as one JSON document.
@MainActor
public final class WorkoutStore {
    public static let key = "workouts.custom.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> [Workout] {
        guard let data = defaults.data(forKey: Self.key),
              let list = try? JSONDecoder().decode([Workout].self, from: data) else { return [] }
        return list
    }

    public func save(_ list: [Workout]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Self.key) }
    }

    @discardableResult
    public func upsert(_ w: Workout) -> [Workout] {
        var list = load()
        var copy = w
        copy.isPreset = false
        if let i = list.firstIndex(where: { $0.id == w.id }) { list[i] = copy } else { list.append(copy) }
        save(list)
        return list
    }

    @discardableResult
    public func delete(id: String) -> [Workout] {
        let list = load().filter { $0.id != id }
        save(list)
        return list
    }
}
