import Foundation
import Testing
@testable import BattleFeature

private struct HudVectors: Decodable {
    struct Clock: Decodable { let id: String; let t: Int64; let expected: BattleHud.Bo3Clock }
    struct Clinched: Decodable { let id: String; let mySets: [Int]; let theirRaw: [Int]; let expected: Bool }
    struct Turn: Decodable {
        let id: String
        let t: Int64
        let myLast: Int64?
        let theirLast: Int64?
        let expected: BattleHud.TurnState
    }
    let bo3Clock: [Clock]
    let bo3Clinched: [Clinched]
    let turns: [Turn]
}

struct BattleHudTests {
    @Test func sharedVectors() throws {
        let v = try JSONDecoder().decode(HudVectors.self, from: RepoFile.data("shared/test-vectors/battles/hud.json"))
        #expect(!v.bo3Clock.isEmpty && !v.bo3Clinched.isEmpty && !v.turns.isEmpty)
        for c in v.bo3Clock { #expect(BattleHud.bo3Clock(c.t) == c.expected, "\(c.id)") }
        for c in v.bo3Clinched { #expect(BattleHud.bo3Clinched(mySets: c.mySets, theirRaw: c.theirRaw) == c.expected, "\(c.id)") }
        for c in v.turns {
            #expect(BattleHud.turnState(t: c.t, myLast: c.myLast, theirLast: c.theirLast) == c.expected, "\(c.id)")
        }
    }

    @Test func setsStopAtAPause() {
        let reps = [BattleRules.Rep(t: 1000, q: 80, round: 0), BattleRules.Rep(t: 2500, q: 80, round: 0),
                    BattleRules.Rep(t: 6000, q: 80, round: 0), BattleRules.Rep(t: 136_000, q: 80, round: 1)]
        #expect(BattleHud.mySets(reps) == [2, 1, 0])
    }
}
