import Foundation
import Testing
@testable import AlarmDomain

enum RepoFile {
    static func url(_ relative: String, file: StaticString = #filePath) -> URL {
        // .../ios/Packages/AlarmDomain/Tests/AlarmDomainTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent(relative)
    }
}

private struct OccJSON: Codable, Equatable {
    let occurrenceId: String
    let alarmId: String
    let localDate: String
    let instant: String
    let countsForChallenge: Bool
}

private struct OccCase: Decodable {
    struct Expected: Decodable {
        let occurrences: [OccJSON]
        let challengeByLocalDate: [String: String?]
    }

    let id: String
    let timeZone: String
    let from: String
    let horizonDays: Int
    let schedules: [AlarmSchedule]
    let expected: Expected
}

private struct ValidationFile: Decodable {
    struct Case: Decodable {
        let id: String
        let schedule: AlarmSchedule
        let expectedErrors: [String]
    }

    let today: String
    let cases: [Case]
}

private struct PlanJSON: Codable, Equatable {
    let osAlarmId: String
    let occurrenceId: String
    let alarmId: String
    let role: String
    let fireAt: String
    let countsForChallenge: Bool
}

private struct NextJSON: Codable, Equatable {
    let occurrenceId: String
    let fireAt: String
}

private struct PlanFile: Decodable {
    struct IDCase: Decodable {
        let occurrenceId: String
        let role: String
        let osAlarmId: String
    }

    struct Case: Decodable {
        struct Expected: Decodable {
            let ios: [PlanJSON]
            let androidNext: [String: NextJSON?]
        }

        let id: String
        let timeZone: String
        let from: String
        let windowDays: Int
        let nagCount: Int
        let schedules: [AlarmSchedule]
        let expected: Expected
    }

    let osAlarmIds: [IDCase]
    let cases: [Case]
}

private func iso(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: d)
}

private func parseISO(_ s: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: s))
}

private func zone(_ name: String) throws -> TimeZone {
    try #require(TimeZone(identifier: name))
}

/// Runs the shared alarm vectors — Android AlarmVectorsTest runs the same files (CLAUDE.md §4.1).
@Suite("Alarm vectors")
struct AlarmVectorTests {
    @Test func occurrenceVectors() throws {
        let dir = RepoFile.url("shared/test-vectors/alarm-occurrences")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count >= 25)
        for file in files {
            let c = try JSONDecoder().decode(OccCase.self, from: Data(contentsOf: file))
            let tz = try zone(c.timeZone)
            let occ = AlarmOccurrences.all(c.schedules, from: try parseISO(c.from), zone: tz, horizonDays: c.horizonDays)
            let actual = occ.map {
                OccJSON(occurrenceId: $0.occurrenceID, alarmId: $0.alarmID, localDate: $0.localDate.description,
                        instant: iso($0.instant), countsForChallenge: $0.countsForChallenge)
            }
            #expect(actual == c.expected.occurrences, "\(c.id)")
            var challenge: [String: String?] = [:]
            for d in Set(occ.map(\.localDate)) {
                challenge[d.description] = .some(AlarmOccurrences.challengeOccurrence(on: d, in: occ)?.occurrenceID)
            }
            #expect(challenge == c.expected.challengeByLocalDate, "\(c.id) challenge")
        }
    }

    @Test func validationVectors() throws {
        let file = try JSONDecoder().decode(ValidationFile.self,
                                            from: Data(contentsOf: RepoFile.url("shared/test-vectors/alarm-validation/cases.json")))
        let today = try #require(LocalDate(file.today))
        for c in file.cases {
            #expect(AlarmValidation.errors(c.schedule, today: today) == Set(c.expectedErrors), "\(c.id)")
        }
    }

    @Test func planVectors() throws {
        let file = try JSONDecoder().decode(PlanFile.self,
                                            from: Data(contentsOf: RepoFile.url("shared/test-vectors/alarm-plan/cases.json")))
        for idCase in file.osAlarmIds {
            #expect(AlarmPlan.osAlarmID(occurrenceID: idCase.occurrenceId, role: idCase.role).uuidString.lowercased()
                    == idCase.osAlarmId)
        }
        for c in file.cases {
            let tz = try zone(c.timeZone)
            let from = try parseISO(c.from)
            let plan = AlarmPlan.windowPlan(c.schedules, from: from, zone: tz, windowDays: c.windowDays, nagCount: c.nagCount)
                .map {
                    PlanJSON(osAlarmId: $0.osAlarmID.uuidString.lowercased(), occurrenceId: $0.occurrenceID, alarmId: $0.alarmID,
                             role: $0.role, fireAt: iso($0.fireAt), countsForChallenge: $0.countsForChallenge)
                }
            #expect(plan == c.expected.ios, "\(c.id) window plan")
            let next = AlarmPlan.nextPerAlarm(c.schedules, from: from, zone: tz)
                .mapValues { o in o.map { NextJSON(occurrenceId: $0.occurrenceID, fireAt: iso($0.instant)) } }
            #expect(next == c.expected.androidNext, "\(c.id) next")
        }
    }

    @Test func scheduleRoundTripsThroughJSON() throws {
        let s = AlarmSchedule.newDefault(id: "a0000000-0000-4000-8000-000000000001")
        let back = try JSONDecoder().decode(AlarmSchedule.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(AlarmValidation.errors(s, today: LocalDate(year: 2026, month: 10, day: 19)).isEmpty)
    }

    @Test func everyModeDefaultIsValid() {
        for t in ModeType.allCases {
            var s = AlarmSchedule.newDefault(id: "x")
            s.mode = .defaults(for: t)
            #expect(AlarmValidation.errors(s, today: LocalDate(year: 2026, month: 10, day: 19)).isEmpty, "\(t)")
        }
    }

    @Test func localDateParsingAndArithmetic() {
        #expect(LocalDate("2026-02-30") == nil)
        #expect(LocalDate("2026-10-19")?.weekday == .mon)
        #expect(LocalDate("2026-12-31")?.adding(days: 1).description == "2027-01-01")
        #expect(LocalDate("2026-11-01")?.days(until: LocalDate(year: 2026, month: 11, day: 30)) == 29)
    }

    @Test func nagChainStopsBeforeDeadline() throws {
        let o = Occurrence(occurrenceID: "a:2026-10-20", alarmID: "a", localDate: LocalDate(year: 2026, month: 10, day: 20),
                           instant: try parseISO("2026-10-20T04:30:00Z"), countsForChallenge: true)
        let chain = AlarmPlan.nagChain(for: o, firstAt: o.instant.addingTimeInterval(27 * 60), count: 3, startingRole: 4)
        #expect(chain.map(\.role) == ["nag4", "nag5"])   // +27, +29; +31 is past the deadline
    }
}
