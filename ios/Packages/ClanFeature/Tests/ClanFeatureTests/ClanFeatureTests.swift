import Foundation
import Testing
@testable import ClanFeature

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
