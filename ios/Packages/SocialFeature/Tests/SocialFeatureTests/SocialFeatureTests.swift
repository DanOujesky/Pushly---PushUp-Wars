import Foundation
import Testing
@testable import SocialFeature

enum RepoFile {
    static func data(_ name: String, file: StaticString = #filePath) throws -> Data {
        // .../ios/Packages/SocialFeature/Tests/SocialFeatureTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent("shared/contracts/fixtures/\(name)"))
    }
}

private struct Boom: Error {}

private func service(friends: Data = Data(), feed: Data = Data("[]".utf8), board: Data = Data(),
                     kudos: @escaping @Sendable (Int) async throws -> Int = { _ in 1 }) -> SocialService {
    SocialService(
        listFriends: { friends }, search: { _ in Data("[]".utf8) }, sendRequest: { _ in "pending" },
        respond: { _, _ in "friends" }, remove: { _ in "none" }, block: { _ in "blocked" }, unblock: { _ in "none" },
        feed: { feed }, kudos: kudos, leaderboard: { _, _, _ in board })
}

struct ContractTests {
    @Test func decodesFixtures() throws {
        let board = try JSONDecoder().decode(Leaderboard.self, from: RepoFile.data("leaderboard.json"))
        #expect(board.rows.count == 4)
        #expect(board.rows[0].user.anonymous == true)
        #expect(board.me?.rank == 3)
        let friends = try JSONDecoder().decode(FriendsList.self, from: RepoFile.data("friends.json"))
        #expect(friends.friends.count == 2)
        let feed = try JSONDecoder().decode([FeedItem].self, from: RepoFile.data("friend_feed.json"))
        #expect(feed.first?.payload["reps"]?.int == 25)
        #expect(FriendsModel.describe(try #require(feed.first)) == "beat the wake challenge · 25 push-ups")
        let search = try JSONDecoder().decode([UserCard].self, from: RepoFile.data("user_search.json"))
        #expect(search.first?.relation == "friends")
    }
}

@MainActor
struct FriendsModelTests {
    @Test func kudosIsOptimisticAndRollsBack() async throws {
        let feed = try RepoFile.data("friend_feed.json")
        var json = try #require(try JSONSerialization.jsonObject(with: feed) as? [[String: Any]])
        json[0]["kudosByMe"] = false
        json[0]["kudos"] = 0
        let fresh = try JSONSerialization.data(withJSONObject: json)
        let friends = try RepoFile.data("friends.json")
        let model = FriendsModel(service: service(friends: friends, feed: fresh, kudos: { _ in throw Boom() }))
        await model.load()
        #expect(model.feed.count == 1)
        await model.kudos(model.feed[0])
        #expect(model.feed[0].kudos == 0)
        #expect(!model.feed[0].kudosByMe)
    }
}

@MainActor
struct RanksModelTests {
    @Test func cachesFor60SecondsAndPinsMe() async throws {
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let counter = Counter()
        var raw = try #require(try JSONSerialization.jsonObject(with: RepoFile.data("leaderboard.json")) as? [String: Any])
        var rows = try #require(raw["rows"] as? [[String: Any]])
        rows.remove(at: 2)                       // my row is not in the top list
        raw["rows"] = rows
        let data = try JSONSerialization.data(withJSONObject: raw)
        let svc = SocialService(
            listFriends: { Data() }, search: { _ in Data() }, sendRequest: { _ in "" }, respond: { _, _ in "" },
            remove: { _ in "" }, block: { _ in "" }, unblock: { _ in "" }, feed: { Data() }, kudos: { _ in 0 },
            leaderboard: { _, _, _ in await counter.hit(); return data })
        let model = RanksModel(service: svc, now: { clock.now })
        await model.load()
        await model.load()
        let first = await counter.count
        #expect(first == 1)
        clock.now = Date(timeIntervalSince1970: 61)
        await model.load()
        let second = await counter.count
        #expect(second == 2)
        #expect(model.pinnedMe?.rank == 3)
        await model.select(board: .streak)
        #expect(model.period == "current")
    }
}

actor Counter {
    var count = 0
    func hit() { count += 1 }
}

/// Rich player profile (D-080) — same expectations as Android UserProfileTest.
struct UserProfileTests {
    @Test func richProfileDecodes() throws {
        let p = try #require(try JSONDecoder().decode(UserProfile?.self, from: RepoFile.data("user_profile.json")))
        #expect(p.clan?.name == "Iron Wolves")
        #expect(p.clan?.role == "co_leader")
        let s = try #require(p.stats)
        #expect(s.rank == 184)
        #expect(s.last7?.count == 7)
        #expect(s.battles?.played == 30)
        #expect(s.battles?.form.first == "W")
        #expect(Int(((s.battles?.winRate ?? 0) * 100).rounded()) == 60)
    }

    @Test func profileTexts() {
        #expect(ProfileText.since("2026-10") == "Oct 2026")
        #expect(ProfileText.since("bad") == "bad")
        #expect(ProfileText.league(.init(league: "silver", tier: "III")) == "Silver III")
        #expect(ProfileText.lastWeekLetters().count == 7)
        #expect(ProfileHero.flag("cz") == "🇨🇿")
    }
}
