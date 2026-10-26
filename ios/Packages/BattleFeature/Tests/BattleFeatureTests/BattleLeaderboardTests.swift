import Foundation
import Testing
@testable import BattleFeature

/// Leaderboard in the Battle tab + Arena Bot (D-075).
struct BattleLeaderboardTests {
    @Test func trophyBoardDecodesTheFixture() throws {
        let board = try JSONDecoder().decode(TrophyBoard.self, from: RepoFile.data("shared/contracts/fixtures/leaderboard.json"))
        #expect(!board.rows.isEmpty)
        #expect(board.rows[0].rank == 1)
        #expect(board.rows[0].user.anonymous == true)
    }

    @Test func clanBoardDecodesTheFixture() throws {
        struct Payload: Decodable { let rows: [ClanBoardRow] }
        let rows = try JSONDecoder().decode(Payload.self, from: RepoFile.data("shared/contracts/fixtures/clan_leaderboard.json")).rows
        #expect(!rows.isEmpty)
        #expect(rows[0].rank == 1)
        #expect(!rows[0].clan.name.isEmpty)
    }

    @Test func arenaBotStepsInAfterTenSeconds() {
        // the server refuses matchmaking_bot() before 9 s in the queue (migration 0031)
        #expect(BattleHubModel.arenaBotAfterS == 10)
    }
}
