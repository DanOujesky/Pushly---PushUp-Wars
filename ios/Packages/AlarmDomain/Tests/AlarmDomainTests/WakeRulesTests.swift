import Foundation
import Testing
@testable import AlarmDomain

/// Shared wake vectors — Android WakeRulesTest and the server (supabase/tests/041_*) run the same files.
@Suite("Wake rules vectors")
struct WakeRulesTests {
    struct DecisionFile: Decodable {
        struct Case: Decodable {
            let id: String
            let mode: ChallengeMode
            let t0: Int64
            let now: Int64
            let session: WakeRules.Session
            let expected: WakeRules.Decision
        }

        let cases: [Case]
    }

    struct PointsFile: Decodable {
        struct Case: Decodable {
            let id: String
            let finalTargetReps: Int
            let mode: String
            let snoozesUsed: Int
            let avgQuality: Int
            let expectedPoints: Int
        }

        let cases: [Case]
    }

    @Test func decisions() throws {
        let data = try Data(contentsOf: RepoFile.url("shared/test-vectors/wake/decisions.json"))
        let file = try JSONDecoder().decode(DecisionFile.self, from: data)
        #expect(file.cases.count >= 20)
        for c in file.cases {
            #expect(WakeRules.decide(mode: c.mode, t0: c.t0, now: c.now, session: c.session) == c.expected, "\(c.id)")
        }
    }

    @Test func points() throws {
        let data = try Data(contentsOf: RepoFile.url("shared/test-vectors/wake/points.json"))
        for c in try JSONDecoder().decode(PointsFile.self, from: data).cases {
            #expect(WakeRules.points(finalTargetReps: c.finalTargetReps, mode: c.mode, snoozesUsed: c.snoozesUsed,
                                     avgQuality: c.avgQuality) == c.expectedPoints, "\(c.id)")
        }
    }
}
