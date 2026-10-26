import Foundation
import Testing
@testable import ClanFeature
import DesignSystem

enum RepoFile {
    static func data(_ name: String, file: StaticString = #filePath) throws -> Data {
        // .../ios/Packages/ClanFeature/Tests/ClanFeatureTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent("shared/contracts/fixtures/\(name)"))
    }
}

struct ClanContractTests {
    @Test func decodesFixtures() throws {
        let home = try JSONDecoder().decode(ClanHome?.self, from: RepoFile.data("clan.json"))
        let h = try #require(home)
        #expect(h.summary.tag == "IRONW")
        #expect(h.summary.myRole == "leader")
        #expect(h.war?.isLive == true)
        #expect(h.war?.clans.map(\.clan.tag) == ["IRONW", "NIGHT", "REDFO"])
        #expect(h.warState?.last?.result?.rank == 1)
        #expect(h.members.count >= 2)
        let none = try JSONDecoder().decode(ClanHome?.self, from: Data("null".utf8))
        #expect(none == nil)
        let messages = try JSONDecoder().decode([ClanMessage].self, from: RepoFile.data("clan_messages.json"))
        #expect(messages.first?.kind == "system")
        let search = try JSONDecoder().decode([ClanSummary].self, from: RepoFile.data("clan_search.json"))
        #expect(!search.isEmpty)
    }
}

struct ClanRoleTests {
    @Test func permissionsMatchTheServer() {
        #expect(ClanRole.leader.assignable(to: .member) == [.coLeader, .elder])
        #expect(ClanRole.coLeader.assignable(to: .member) == [.elder])
        #expect(ClanRole.coLeader.assignable(to: .coLeader).isEmpty)
        #expect(ClanRole.elder.assignable(to: .member).isEmpty)
        #expect(ClanRole.elder.canKick(.member))
        #expect(!ClanRole.elder.canKick(.elder))
        #expect(!ClanRole.coLeader.canKick(.leader))
        #expect(!ClanRole.member.canKick(.member))
        #expect(ClanRole.coLeader.canEditSettings && !ClanRole.elder.canEditSettings)
    }

    @Test func friendlyErrors() {
        struct E: Error, CustomStringConvertible { let description: String }
        #expect(ClanModel.message(for: E(description: "hint: taken")) == "That name or tag is taken.")
        #expect(ClanModel.message(for: E(description: "rate limited")) == "Slow down a little and try again.")
    }
}

struct WarHistoryTests {
    @Test func decodesFixtures() throws {
        let wars = try JSONDecoder().decode([ClanWarResult].self, from: RepoFile.data("clan_war_results.json"))
        #expect(wars.first?.rank == 1 && wars.first?.of == 3)
        #expect(wars.first?.clans.count == 3)
        #expect(wars.first?.letter == "W")
        let chests = try JSONDecoder().decode(WarChests.self, from: RepoFile.data("war_chests.json"))
        #expect(chests.unopened.first?.xp == 250)
        #expect(chests.medals.gold == 3)
    }

    @Test func streak() {
        func war(_ rank: Int, of: Int = 3) -> ClanWarResult {
            ClanWarResult(id: UUID().uuidString, weekStart: "2026-10-12", rank: rank, of: of, score: 1, ratingDelta: 0, clans: [])
        }
        #expect(WarStreak.current([war(1), war(1), war(2)])?.count == 2)
        #expect(WarStreak.current([war(3), war(1)])?.letter == "L")
        #expect(WarStreak.current([war(1, of: 1)])?.letter == "L")    // alone is not a win
        #expect(WarStreak.current([]) == nil)
    }
}

/// War detail + record (D-079) — same expectations as Android ClanWarDetailTest.
struct ClanWarDetailTests {
    @Test func detailDecodesWithFighters() throws {
        let d = try JSONDecoder().decode(ClanWarDetail.self, from: RepoFile.data("clan_war_detail.json"))
        #expect(d.days.count == 7)
        let mine = try #require(d.mySide)
        #expect(mine.isMine)
        #expect(mine.fighters.map(\.user.username) == ["ana_fit", "eva_k"])
        #expect(mine.fighters.first?.days == [0, 120, 0, 0, 0, 0, 0])
        #expect(mine.active == 2 && mine.idle.isEmpty)
        #expect(mine.bestDay == 120)
        #expect(d.clans.count == 3)
        #expect(d.war.isFinished)
        let results = try JSONDecoder().decode([ClanWarResult].self, from: RepoFile.data("clan_war_results.json"))
        #expect(results.first?.mvp?.username == "ana_fit")
        #expect(results.first?.contributors == 2)
    }

    @Test func idleMembersAreFlagged() {
        let card = MemberCard(id: "u", username: "lazy")
        let side = ClanWarDetail.Side(clanId: "c", isMine: true, fighters: [
            .init(user: card, points: 0, raw: 0, days: Array(repeating: 0, count: 7), inClan: true),
            .init(user: MemberCard(id: "g", username: "gone"), points: 0, raw: 0, days: Array(repeating: 0, count: 7), inClan: false),
        ])
        #expect(side.idle.map(\.user.username) == ["lazy"])
        #expect(side.active == 0)
    }

    @Test func record() {
        func war(_ rank: Int, of: Int = 3, delta: Int = 0) -> ClanWarResult {
            ClanWarResult(id: UUID().uuidString, weekStart: "2026-10-12", rank: rank, of: of, score: 1, ratingDelta: delta, clans: [])
        }
        let r = WarRecord([war(1, delta: 30), war(2, delta: 0), war(1, delta: 30), war(1, delta: 15), war(3, delta: -30)])
        #expect(r.played == 5 && r.wins == 3)
        #expect(r.trophyNet == 45)
        #expect(r.bestStreak == 2)
        #expect(r.form == [1, 2, 1, 1, 3])
        #expect(WarRecord([]).winRate == 0)
        #expect(WarDates.week("2026-10-19") == "19 Oct – 25 Oct")
    }
}

/// Clan Wars v2 (D-078) — same expectations as Android ClanWarStateTest.
struct ClanWarStateTests {
    @Test func stateDecodesAndSummarises() throws {
        let state = try JSONDecoder().decode(ClanWarState.self, from: RepoFile.data("clan_war_state.json"))
        let war = try #require(state.current)
        #expect(war.isLive)
        #expect(war.gap == 35)                                  // 80 vs best rival 45
        #expect(war.myRank == 1)
        #expect(war.rivals.count == 2)
        #expect(war.mine?.stakes != nil)
        #expect(war.feed.first?.mine == false)
        #expect(war.rally?.available == true)
        let last = try #require(state.last)
        #expect(last.isFinished && last.result?.ratingDelta == 30)
        #expect(last.clans.first?.ratingDelta == 30)
    }

    @Test func resultsAreShownOnce() {
        let id = "test-\(UUID().uuidString)"
        #expect(!WarResultSeen.contains(id))
        WarResultSeen.mark(id)
        #expect(WarResultSeen.contains(id))
    }

    @Test func clockText() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(WarClock.until("1970-01-03T04:00:00Z", now: now) == "2 d 4 h")
        #expect(WarClock.until("1970-01-01T03:12:00Z", now: now) == "3 h 12 min")
        #expect(WarClock.until("1969-12-31T00:00:00Z", now: now) == nil)
    }
}

/// Clan badges (D-074): fixture badge decodes; older clans get a stable look from the tag.
struct ClanBadgeTests {
    @Test func fixtureBadgeDecodes() throws {
        let home = try #require(try JSONDecoder().decode(ClanHome?.self, from: RepoFile.data("clan.json")))
        #expect(home.summary.badge == ClanBadgeStyle(shape: "shield", color: "flame", emblem: "wolf"))
        // the rivals never picked one: {}
        #expect(home.war?.rivals.first?.clan.badge == ClanBadgeStyle())
    }

    @Test func emptyBadgeIsPickedFromTheTag() {
        // "ABC" = 65 + 66 + 67 = 198 → colour 198 % 8 = 6 (diamond), emblem free[(198 / 8) % 8 = 0] (flame). Same on Android.
        let r = ClanBadgeStyle().resolved(tag: "abc")
        #expect(r.shape == "shield")
        #expect(r.color == "diamond")
        #expect(r.emblem.id == "flame")
        let picked = ClanBadgeStyle(shape: "hex", color: "lime", emblem: "dragon").resolved(tag: "abc")
        #expect(picked.shape == "hex" && picked.color == "lime" && picked.emblem.id == "dragon")
        // unknown values fall back instead of breaking the badge
        #expect(ClanBadgeStyle(shape: "star", color: "rainbow", emblem: "unicorn").resolved(tag: "abc").color == "diamond")
    }

    @Test @MainActor func updateSendsTheBadge() async {
        final class Box: @unchecked Sendable { var badge: [String: String]?; var policy: String? }
        let box = Box()
        let service = ClanService(
            home: { Data("null".utf8) }, clan: { _ in Data() }, search: { _ in Data("[]".utf8) },
            create: { _, _, _, _, _ in Data() },
            update: { badge, _, policy in box.badge = badge; box.policy = policy; return Data("{}".utf8) },
            join: { _, _ in "" }, respond: { _, _ in "" }, leave: { "" }, kick: { _ in }, setRole: { _, _ in }, transfer: { _ in },
            messages: { _ in Data("[]".utf8) }, send: { _, _ in })
        let model = ClanModel(service: service)
        let ok = await model.update(badge: ClanBadgeStyle(shape: "round", color: "gold", emblem: "crown"), description: nil, policy: "request")
        #expect(ok)
        #expect(box.badge == ["shape": "round", "color": "gold", "emblem": "crown"])
        #expect(box.policy == "request")
    }
}

struct ChatLayoutTests {
    private func msg(_ id: Int, _ user: String?, _ at: String, kind: String = "text") -> ClanMessage {
        ClanMessage(id: id, kind: kind, body: "x",
                    user: user.map { ClanMessage.Author(id: $0, username: $0, avatarPreset: nil) }, createdAt: at)
    }

    @Test func groupsConsecutiveMessagesBySameAuthor() {
        let a = msg(1, "u1", "2026-10-21T10:00:00Z")
        let b = msg(2, "u1", "2026-10-21T10:03:20Z")
        let c = msg(3, "u2", "2026-10-21T10:04:00Z")
        let d = msg(4, "u2", "2026-10-21T10:20:00Z")
        #expect(ChatLayout.startsGroup(a, after: nil))
        #expect(!ChatLayout.startsGroup(b, after: a))
        #expect(ChatLayout.startsGroup(c, after: b))
        #expect(ChatLayout.startsGroup(d, after: c)) // > 5 min gap
        #expect(ChatLayout.startsGroup(msg(5, nil, "2026-10-21T10:21:00Z", kind: "system"), after: d))
    }

    @Test func daySeparatorOnNewDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let a = msg(1, "u1", "2026-10-21T23:59:00Z")
        let b = msg(2, "u1", "2026-10-22T00:01:00Z")
        #expect(ChatLayout.newDay(a, after: nil, calendar: cal))
        #expect(ChatLayout.newDay(b, after: a, calendar: cal))
        #expect(!ChatLayout.newDay(a, after: a, calendar: cal))
    }

    @Test func parsesFractionalSeconds() {
        #expect(ChatLayout.date("2026-10-21T10:03:20.123456+00:00") != nil)
        #expect(ChatLayout.date("2026-10-21T10:03:20Z") != nil)
    }
}
