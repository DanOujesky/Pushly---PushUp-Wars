import Foundation
import Testing
@testable import AlarmDomain

struct WidgetSnapshotTests {
    private let zone = TimeZone(identifier: "Europe/Prague") ?? .gmt

    @Test func upcomingIsSortedEnabledAndCapped() throws {
        var a = AlarmSchedule.newDefault(id: "a")
        a.label = "Gym"
        var b = AlarmSchedule.newDefault(id: "b")
        b.enabled = false
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-21T10:00:00Z"))
        let list = WidgetSnapshot.upcoming([a, b], from: now, zone: zone)
        #expect(!list.isEmpty && list.count <= WidgetSnapshot.maxUpcoming)
        #expect(list.allSatisfy { $0.at > now && $0.label == "Gym" })
        #expect(list == list.sorted { $0.at < $1.at })
    }

    @Test func repsTodayExpiresAtMidnight() throws {
        let snap = WidgetSnapshot(upcoming: [], streak: 3, repsToday: 40, today: "2026-10-21")
        let noon = try #require(ISO8601DateFormatter().date(from: "2026-10-21T10:00:00Z"))
        let tomorrow = try #require(ISO8601DateFormatter().date(from: "2026-10-22T10:00:00Z"))
        #expect(snap.repsToday(at: noon, zone: zone) == 40)
        #expect(snap.repsToday(at: tomorrow, zone: zone) == nil)
    }
}
