import Foundation
import Testing
@testable import BattleFeature

/// Shared vectors (shared/test-vectors/battles/recap.json) — Android runs the same file (D-077).
struct BattleRecapTests {
    struct Vectors: Decodable {
        struct Margin: Decodable {
            var kind: String
            var n: Int?
            var ms: Int64?
            var mine: Int?
            var theirs: Int?
            var byMe: Bool?
        }

        struct Expected: Decodable {
            var outcome: String
            var mine: Int
            var theirs: Int
            var margin: Margin
            var close: Bool
        }

        struct Case: Decodable {
            var id: String
            var battle: Battle
            var expected: Expected
        }

        var cases: [Case]
    }

    private func margin(_ m: Vectors.Margin) -> BattleRecap.Margin? {
        switch m.kind {
        case "reps": m.n.map { .reps($0) }
        case "time": m.ms.map { .time($0) }
        case "rounds": .rounds(m.mine ?? 0, m.theirs ?? 0)
        case "form": .form
        case "forfeit": .forfeit(byMe: m.byMe ?? false)
        case "turnMissed": .turnMissed(byMe: m.byMe ?? false)
        case "draw": .draw
        case "void": .void
        default: nil
        }
    }

    @Test func matchesSharedVectors() throws {
        let v = try JSONDecoder().decode(Vectors.self, from: RepoFile.data("shared/test-vectors/battles/recap.json"))
        #expect(v.cases.count >= 10)
        for c in v.cases {
            let r = BattleRecap(c.battle)
            #expect(r.outcome.rawValue == c.expected.outcome, "\(c.id)")
            #expect(r.mine == c.expected.mine, "\(c.id)")
            #expect(r.theirs == c.expected.theirs, "\(c.id)")
            #expect(r.margin == margin(c.expected.margin), "\(c.id)")
            #expect(r.isClose == c.expected.close, "\(c.id)")
        }
    }

    @Test func summaryCountsCloseCallsAndTrophies() throws {
        let v = try JSONDecoder().decode(Vectors.self, from: RepoFile.data("shared/test-vectors/battles/recap.json"))
        let s = HistorySummary(v.cases.map(\.battle))
        #expect(s.closeLosses == 2)   // lost by one, lost on form
        #expect(s.clutchWins == 3)    // won by one, photo finish, 2–1
        #expect(s.trophyNet == 2)     // -18 + 20
        #expect(s.form.count == 10)
        #expect(s.form.first == .loss)
    }

    @Test func linesReadNaturally() {
        #expect(BattleRecap(outcome: .loss, mine: 24, theirs: 25, margin: .reps(1)).line == "Lost by 1 push-up")
        #expect(BattleRecap(outcome: .win, mine: 20, theirs: 20, margin: .time(400)).line == "Won by 0.4 s")
    }
}
