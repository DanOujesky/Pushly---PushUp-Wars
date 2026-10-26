import Foundation
import Testing
@testable import BattleFeature

/// Battle tab lobby (D-071): arena header from get_battle_stats, friend challenges are always friendly.
@MainActor
struct BattleHubTests {
    final class Invites: @unchecked Sendable {
        var ranked: [Bool] = []
    }

    nonisolated private static func service(_ invites: Invites) -> BattleService {
        let none: @Sendable () async throws -> Data = { throw CancellationError() }
        return BattleService(
            invites: { Data(#"{"incoming":[],"outgoing":[]}"#.utf8) }, friends: none,
            invite: { _, _, ranked in
                invites.ranked.append(ranked)
                return Data("{}".utf8)
            },
            respond: { _, _ in throw CancellationError() }, join: { _ in throw CancellationError() }, status: none,
            leaveQueue: {}, get: { _ in throw CancellationError() }, ready: { _ in throw CancellationError() },
            push: { _, _ in }, finish: { _ in throw CancellationError() }, forfeit: { _ in throw CancellationError() },
            history: none, ghost: { _ in throw CancellationError() },
            stats: { try RepoFile.data("shared/contracts/fixtures/battle_stats.json") })
    }

    @Test func arenaComesFromBattleStats() async throws {
        let model = BattleHubModel(service: Self.service(Invites()))
        await model.load()
        let arena = try #require(model.arena)
        #expect(arena.trophies == 1340)
        #expect(arena.league == "gold" && arena.tier == "III")
        #expect(arena.rank == 482)
        // gold III starts at 1200, next step 1466 → (1340 − 1200) / 266
        #expect(abs(arena.progress - 140.0 / 266.0) < 0.0001)
    }

    @Test func friendRequestsShowAndCanBeAccepted() async {
        final class Answers: @unchecked Sendable { var accepted: [String] = [] }
        let answers = Answers()
        let none: @Sendable () async throws -> Data = { throw CancellationError() }
        let service = BattleService(
            invites: none,
            friends: {
                Data(#"{"friends":[],"incoming":[{"id":"u2","username":"kamo"}],"outgoing":[],"blocked":[]}"#.utf8)
            },
            invite: { _, _, _ in Data() }, respond: { _, _ in Data() }, join: { _ in Data() }, status: none,
            leaveQueue: {}, get: { _ in Data() }, ready: { _ in Data() }, push: { _, _ in }, finish: { _ in Data() },
            forfeit: { _ in Data() }, history: none, ghost: { _ in Data() },
            respondFriend: { id, accept in if accept { answers.accepted.append(id) } })
        let model = BattleHubModel(service: service)
        await model.loadFriends()
        #expect(model.friendRequests.map(\.username) == ["kamo"])
        await model.respondFriend("u2", accept: true)
        #expect(answers.accepted == ["u2"])
    }

    @Test func friendChallengesAreNeverRanked() async {
        let invites = Invites()
        let model = BattleHubModel(service: Self.service(invites))
        await model.challenge(FriendPick(id: "f1", username: "kamo", avatarPreset: nil), mode: .speed)
        #expect(invites.ranked == [false])
    }

    @Test func topLeagueHasFullProgress() throws {
        var arena = try JSONDecoder().decode(ArenaStatus.self,
                                             from: RepoFile.data("shared/contracts/fixtures/battle_stats.json"))
        arena.next = nil
        #expect(arena.progress == 1)
    }

    @Test func everyModeHasABlurb() {
        for mode in BattleMode.allCases { #expect(!modeBlurb(mode).isEmpty) }
    }

    private struct LeagueVectors: Decodable {
        struct Case: Decodable {
            let trophies: Int
            let league: String
            let tier: String?
        }

        let cases: [Case]
    }

    @Test func ladderMatchesTheSharedLeagueVectors() throws {
        let v = try JSONDecoder().decode(LeagueVectors.self, from: RepoFile.data("shared/test-vectors/trophies/leagues.json"))
        #expect(v.cases.count > 10)
        for c in v.cases {
            let got = LeagueLadder.leagueFor(c.trophies)
            #expect(got.league == c.league && got.tier == c.tier, "\(c.trophies)")
        }
        #expect(LeagueLadder.rungs.count == 17)
        #expect(LeagueLadder.rungs.map(\.from) == ArenaStatus.steps)
    }

    @Test func friendSearchNeedsTwoLetters() async {
        let model = BattleHubModel(service: Self.service(Invites()))
        await model.searchUsers("a")
        #expect(model.userHits.isEmpty)
    }
}
