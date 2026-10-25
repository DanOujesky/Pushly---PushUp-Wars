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
        #expect(h.summary.tag == "IRON")
        #expect(h.summary.myRole == "co_leader")
        #expect(h.war?.score.us == 280)
        #expect(h.war?.opponent?.tag == "OWL")
        #expect(h.members.count >= 5)
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
        let wars = try JSONDecoder().decode([ClanWarRecord].self, from: RepoFile.data("clan_war_history.json"))
        #expect(wars.first?.opponent?.tag == "OWL")
        #expect(wars.last?.opponent == nil)
        let chests = try JSONDecoder().decode(WarChests.self, from: RepoFile.data("war_chests.json"))
        #expect(chests.unopened.first?.xp == 250)
        #expect(chests.medals.gold == 3)
    }

    @Test func streak() {
        func war(_ won: Bool?, draw: Bool = false) -> ClanWarRecord {
            ClanWarRecord(id: UUID().uuidString, weekStart: "2026-10-12", opponent: nil, us: 1, them: 0, won: won, draw: draw,
                          reason: "score")
        }
        #expect(WarStreak.current([war(true), war(true), war(false)])?.count == 2)
        #expect(WarStreak.current([war(false), war(true)])?.letter == "L")
        #expect(WarStreak.current([war(nil, draw: true), war(true)]) == nil)
        #expect(WarStreak.current([]) == nil)
    }
}

/// Clan Wars with more fight (D-068) — same expectations as Android ClanWarActionTest.
struct ClanWarActionTests {
    @Test func warExtrasDecodeAndSummarise() throws {
        let war = try #require(try JSONDecoder().decode(ClanHome?.self, from: RepoFile.data("clan.json"))?.war)
        #expect(war.gap == 30)
        #expect(war.days?.count == 7)
        #expect(war.daysWon.us == 1 && war.daysWon.them == 1)    // Tue ours, Wed theirs
        #expect(war.feed?.first?.side == "us")
        #expect(war.theirTop?.first?.reps == 250)
        #expect(war.rally?.available == true)
    }
}

/// Clan badges (D-074): fixture badge decodes; older clans get a stable look from the tag.
struct ClanBadgeTests {
    @Test func fixtureBadgeDecodes() throws {
        let home = try #require(try JSONDecoder().decode(ClanHome?.self, from: RepoFile.data("clan.json")))
        #expect(home.summary.badge == ClanBadgeStyle(shape: "shield", color: "flame", emblem: "wolf"))
        // the opponent never picked one: {}
        #expect(home.war?.opponent?.badge == ClanBadgeStyle())
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
