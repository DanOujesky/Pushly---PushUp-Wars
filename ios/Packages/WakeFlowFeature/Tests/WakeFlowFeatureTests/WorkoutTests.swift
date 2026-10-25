import Foundation
import Testing
@testable import WakeFlowFeature

private struct WorkoutVectors: Decodable {
    struct Step: Decodable {
        let op: String
        let t: Int64
    }

    struct RawEvent: Decodable {
        let type: String
        let t: Int64
        let set: Int?
        let reps: Int?
        let completed: Bool?
        let next: Int?
        let until: Int64?
    }

    struct Result: Decodable {
        let reps: Int
        let target: Int
        let completed: Bool
    }

    struct Final: Decodable {
        let phase: String
        let index: Int
        let setReps: Int
        let total: Int
        let msLeft: Int64?
    }

    struct RunnerCase: Decodable {
        let id: String
        let workout: Workout
        let steps: [Step]
        let events: [RawEvent]
        let results: [Result]
        let final: Final
        let finalT: Int64
    }

    struct ValidationCase: Decodable {
        let id: String
        let workout: Partial
        let expectedErrors: [String]
    }

    struct Partial: Decodable {
        let name: String
        let everyS: Int?
        let sets: [WorkoutSet]
    }

    struct Planned: Decodable {
        let id: String
        let planned: Int?
    }

    let runner: [RunnerCase]
    let validation: [ValidationCase]
    let plannedReps: [Planned]

    static func load(file: StaticString = #filePath) throws -> WorkoutVectors {
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("shared/test-vectors/workouts/runner.json"))
        return try JSONDecoder().decode(WorkoutVectors.self, from: data)
    }
}

private extension WorkoutRunner.Event {
    init(_ e: WorkoutVectors.RawEvent) throws {
        switch e.type {
        case "setStarted": self = .setStarted(set: e.set ?? -1, t: e.t)
        case "setEnded": self = .setEnded(set: e.set ?? -1, reps: e.reps ?? -1, completed: e.completed ?? false, t: e.t)
        case "restStarted": self = .restStarted(next: e.next ?? -1, until: e.until ?? -1, t: e.t)
        case "done": self = .done(t: e.t)
        default: throw CocoaError(.coderInvalidValue)
        }
    }
}

@Suite struct WorkoutTests {
    @Test func runnerMatchesTheSharedVectors() throws {
        let v = try WorkoutVectors.load()
        #expect(v.runner.count >= 10)
        for c in v.runner {
            var r = WorkoutRunner(workout: c.workout)
            for s in c.steps {
                switch s.op {
                case "start": r.start(s.t)
                case "rep": r.rep(s.t)
                case "tick": r.tick(s.t)
                case "endSet": r.endSet(s.t)
                case "skipRest": r.skipRest(s.t)
                case "finish": r.finish(s.t)
                default: Issue.record("unknown op \(s.op)")
                }
            }
            let expected = try c.events.map(WorkoutRunner.Event.init)
            #expect(r.events == expected, "\(c.id)")
            #expect(r.results == c.results.map { .init(reps: $0.reps, target: $0.target, completed: $0.completed) }, "\(c.id)")
            let snap = r.snapshot(c.finalT)
            #expect(snap.phase.rawValue == c.final.phase, "\(c.id)")
            #expect(snap.index == c.final.index, "\(c.id)")
            #expect(snap.setReps == c.final.setReps, "\(c.id)")
            #expect(snap.total == c.final.total, "\(c.id)")
            #expect(snap.msLeft == c.final.msLeft, "\(c.id)")
        }
    }

    @Test func validationMatchesTheReference() throws {
        for c in try WorkoutVectors.load().validation {
            let w = Workout(name: c.workout.name, everyS: c.workout.everyS, sets: c.workout.sets)
            #expect(w.validationErrors == c.expectedErrors, "\(c.id)")
        }
    }

    @Test func presetsAreValidAndMatchThePlannedTotals() throws {
        let planned = try WorkoutVectors.load().plannedReps
        #expect(Workout.presets.map(\.id) == planned.map(\.id))
        for (p, e) in zip(Workout.presets, planned) {
            #expect(p.validationErrors.isEmpty, "\(p.id)")
            #expect(p.plannedReps == e.planned, "\(p.id)")
            #expect(p.isPreset)
        }
    }

    @Test @MainActor func storeKeepsCustomWorkouts() throws {
        let defaults = try #require(UserDefaults(suiteName: "workouts-\(UUID().uuidString)"))
        let store = WorkoutStore(defaults: defaults)
        #expect(store.load().isEmpty)
        var w = Workout(name: "Mine", sets: [WorkoutSet(kind: .reps, target: 12, restS: 30)])
        store.upsert(w)
        w.name = "Mine v2"
        store.upsert(w)
        #expect(store.load() == [w])
        store.delete(id: w.id)
        #expect(store.load().isEmpty)
    }
}
