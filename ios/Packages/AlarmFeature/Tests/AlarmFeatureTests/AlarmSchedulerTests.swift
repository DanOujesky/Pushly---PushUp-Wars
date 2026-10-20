import AlarmDomain
import Foundation
import Testing
@testable import AlarmFeature

/// Fake AlarmKit: records what is armed.
final class FakeOSClient: AlarmOSClient, @unchecked Sendable {
    private let lock = NSLock()
    var auth: AlarmAuthState = .authorized
    private(set) var armed: [UUID: OSAlarmRequest] = [:]
    var alerting: Set<UUID> = []
    private(set) var scheduleCalls = 0
    private(set) var stopped: [UUID] = []

    func authorizationState() -> AlarmAuthState { lock.withLock { auth } }
    func requestAuthorization() async -> AlarmAuthState { lock.withLock { auth = .authorized; return auth } }
    func currentAlarms() throws -> [OSAlarm] {
        lock.withLock { armed.keys.map { OSAlarm(id: $0, isAlerting: alerting.contains($0)) } }
    }
    func schedule(_ request: OSAlarmRequest) async throws {
        lock.withLock {
            armed[request.id] = request
            scheduleCalls += 1
        }
    }
    func cancel(_ id: UUID) throws { lock.withLock { _ = armed.removeValue(forKey: id) } }
    func stop(_ id: UUID) throws {
        lock.withLock {
            stopped.append(id)
            alerting.remove(id)
            armed.removeValue(forKey: id)
        }
    }

    var requests: [OSAlarmRequest] { lock.withLock { Array(armed.values).sorted { $0.fireAt < $1.fireAt } } }
}

final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ iso: String) { now = ISOInstant.parse(iso) ?? Date() }
}

@MainActor
@Suite("AlarmScheduler (iOS)")
struct AlarmSchedulerTests {
    let prague = TimeZone(identifier: "Europe/Prague") ?? .current

    private func make(_ clock: TestClock, client: FakeOSClient = FakeOSClient()) -> (AlarmScheduler, FakeOSClient) {
        let repo = AlarmRepository(store: InMemoryDocumentStore(), now: { clock.now })
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let zone = prague
        let scheduler = AlarmScheduler(repository: repo, client: client, defaults: defaults, now: { clock.now }, zone: { zone })
        return (scheduler, client)
    }

    private func weekdays(_ id: String, _ time: String) -> AlarmSchedule {
        AlarmSchedule(id: id, label: "Up", weekly: WeeklyTimes(mon: time, tue: time, wed: time, thu: time, fri: time))
    }

    @Test func syncArmsWindowWithNagsAndIsIdempotent() async {
        let clock = TestClock("2026-10-19T10:00:00Z") // Monday noon in Prague
        let (s, client) = make(clock)
        _ = s.repository.save(weekdays("a", "06:30"), zone: prague)
        let first = await s.sync()
        // Tue–Fri next week window (7 days: Tue..Mon) = 5 weekday mornings × (1 main + 3 nags).
        #expect(first.scheduled == 20)
        #expect(client.requests.filter { !$0.isNag }.count == 5)
        let callsAfterFirst = client.scheduleCalls
        let second = await s.sync()
        #expect(second.scheduled == 0 && second.cancelled == 0)
        #expect(client.scheduleCalls == callsAfterFirst)
        #expect(second.nextArmed)
    }

    @Test func disablingCancelsEverything() async {
        let clock = TestClock("2026-10-19T10:00:00Z")
        let (s, client) = make(clock)
        _ = s.repository.save(weekdays("a", "06:30"), zone: prague)
        await s.sync()
        s.repository.setEnabled(id: "a", false, zone: prague)
        let report = await s.sync()
        #expect(report.cancelled == 20)
        #expect(client.requests.isEmpty)
    }

    @Test func notAuthorizedSchedulesNothingAndReportsNotArmed() async {
        let clock = TestClock("2026-10-19T10:00:00Z")
        let client = FakeOSClient()
        client.auth = .denied
        let (s, _) = make(clock, client: client)
        _ = s.repository.save(weekdays("a", "06:30"), zone: prague)
        let report = await s.sync()
        #expect(report.scheduled == 0)
        #expect(!report.nextArmed)
    }

    @Test func finishingCancelsRemainingNagsImmediately() async {
        let clock = TestClock("2026-10-19T10:00:00Z")
        let (s, client) = make(clock)
        _ = s.repository.save(weekdays("a", "06:30"), zone: prague)
        await s.sync()
        clock.now = ISOInstant.parse("2026-10-20T04:31:00Z") ?? clock.now // Tue 06:31 Prague, alarm rang
        let occurrenceID = "a:2026-10-20"
        guard let ring = s.ringState(occurrenceID: occurrenceID, alarmID: "a") else {
            Issue.record("no ring state")
            return
        }
        await s.sessionStarted(ring)
        #expect(client.requests.contains { $0.occurrenceID == occurrenceID && $0.isNag })
        await s.finish(occurrenceID: occurrenceID)
        #expect(!client.requests.contains { $0.occurrenceID == occurrenceID })
        #expect(s.liveRing() == nil)
    }

    @Test func stopWithoutPushupsKeepsNagging() async {
        let clock = TestClock("2026-10-19T10:00:00Z")
        let (s, client) = make(clock)
        _ = s.repository.save(weekdays("a", "06:30"), zone: prague)
        await s.sync()
        clock.now = ISOInstant.parse("2026-10-20T04:37:00Z") ?? clock.now // 06:37, the pre-armed nags have fired
        await s.stopPressed(occurrenceID: "a:2026-10-20", alarmID: "a")
        let nags = client.requests.filter { $0.occurrenceID == "a:2026-10-20" && $0.isNag }
        #expect(nags.count == 3)
        #expect(nags.allSatisfy { $0.fireAt > clock.now })
        #expect(s.liveRing()?.occurrenceId == "a:2026-10-20")
    }

    @Test func escalationSnoozeReplacesNagsWithOneAlarm() async {
        let clock = TestClock("2026-10-19T10:00:00Z")
        let (s, client) = make(clock)
        var alarm = weekdays("a", "06:30")
        alarm.mode = ChallengeMode.defaults(for: .escalation)
        _ = s.repository.save(alarm, zone: prague)
        await s.sync()
        clock.now = ISOInstant.parse("2026-10-20T04:31:00Z") ?? clock.now
        guard let ring = s.ringState(occurrenceID: "a:2026-10-20", alarmID: "a") else {
            Issue.record("no ring state")
            return
        }
        await s.sessionStarted(ring)
        let snoozed = await s.snooze(occurrenceID: "a:2026-10-20")
        #expect(snoozed?.target == 25)
        let pending = client.requests.filter { $0.occurrenceID == "a:2026-10-20" }
        #expect(pending.count == 1)
        #expect(pending.first?.fireAt == clock.now.addingTimeInterval(300))
    }

    @Test func practiceAlarmArmsAndCanStartASession() async {
        let clock = TestClock("2026-10-19T10:00:00Z")
        let (s, client) = make(clock)
        let alarm = weekdays("a", "06:30")
        _ = s.repository.save(alarm, zone: prague)
        #expect(await s.armPractice(alarm))
        guard let practice = client.requests.first(where: \.isPractice) else {
            Issue.record("no practice alarm")
            return
        }
        #expect(practice.fireAt == clock.now.addingTimeInterval(10))
        clock.now = clock.now.addingTimeInterval(15)
        let ring = s.ringState(occurrenceID: practice.occurrenceID, alarmID: "a")
        #expect(ring?.practice == true)
        #expect(ring?.countsForChallenge == false)
    }

    @Test func stuckAlertingAlarmIsStoppedOnReconcile() async {
        let clock = TestClock("2026-10-19T10:00:00Z")
        let (s, client) = make(clock)
        _ = s.repository.save(weekdays("a", "06:30"), zone: prague)
        await s.sync()
        let main = AlarmPlan.osAlarmID(occurrenceID: "a:2026-10-20", role: "main")
        client.alerting = [main]
        clock.now = ISOInstant.parse("2026-10-20T04:35:00Z") ?? clock.now // alerting for 5 min
        await s.reconcile()
        #expect(client.stopped.contains(main))
    }
}
