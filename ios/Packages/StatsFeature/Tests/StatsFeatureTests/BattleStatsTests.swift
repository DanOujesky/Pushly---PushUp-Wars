import Foundation
import Testing
@testable import StatsFeature

/// Trophy-first stats (D-067) — same expectations as Android BattleStatsTest.
struct BattleStatsTests {
    private func fixture() throws -> BattleStats {
        try JSONDecoder().decode(BattleStats.self,
                                 from: Data(contentsOf: RepoFile.url("shared/contracts/fixtures/battle_stats.json")))
    }

    @Test func decodesTheContractFixture() throws {
        let s = try fixture()
        #expect(s.trophies == 1340 && s.league == "gold" && s.tier == "III")
        #expect(s.next?.at == 1466)
        #expect(s.targets.first?.gap == 12)
        #expect(s.recent.count == 2)
    }

    @Test func progressAndWinRate() throws {
        let s = try fixture()
        // Gold III starts at 1200, Gold II at 1466: (1340 − 1200) / 266
        #expect(abs(s.progressToNext - 140.0 / 266.0) < 0.0001)
        #expect(s.record.winRate == 61)    // 23 of 38
        #expect(BattleStats.leagueName("gold", "III").hasSuffix("III"))
    }
}
