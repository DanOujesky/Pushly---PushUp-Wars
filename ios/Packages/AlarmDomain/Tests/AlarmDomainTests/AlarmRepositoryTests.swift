import Foundation
import Testing
@testable import AlarmDomain

private final class Clock: @unchecked Sendable {
    var now: Date

    init(_ iso: String) {
        now = ISOInstant.parse(iso) ?? Date()
    }
}

private let prague = TimeZone(identifier: "Europe/Prague") ?? .current

@MainActor
@Suite("Alarm repository")
struct AlarmRepositoryTests {
    private func repo(_ store: DocumentStore = InMemoryDocumentStore(), clock: Clock) -> AlarmRepository {
        AlarmRepository(store: store, now: { clock.now })
    }

    @Test func saveBumpsVersionPersistsAndQueues() {
        let clock = Clock("2026-10-19T12:00:00Z")
        let store = InMemoryDocumentStore()
        let r = repo(store, clock: clock)
        guard case let .saved(first) = r.save(.newDefault(id: "a"), zone: prague) else {
            Issue.record("not saved")
            return
        }
        #expect(first.version == 1)
        var edited = first
        edited.label = "  Rise  "
        guard case let .saved(second) = r.save(edited, zone: prague) else {
            Issue.record("not saved")
            return
        }
        #expect(second.version == 2)
        #expect(second.label == "Rise")
        #expect(r.document.outbox == [OutboxEntry(alarmId: "a", op: OutboxEntry.upsert, version: 2, queuedAt: "2026-10-19T12:00:00Z")])
        #expect(repo(store, clock: clock).alarms == r.alarms)   // survives an app restart
    }

    @Test func invalidAndTooMany() {
        let clock = Clock("2026-10-19T12:00:00Z")
        let r = repo(clock: clock)
        var bad = AlarmSchedule.newDefault(id: "a")
        bad.mode = ChallengeMode(type: "ringUntilDone", targetReps: 3)
        #expect(r.save(bad, zone: prague) == .invalid(["mode.targetReps"]))
        for i in 0..<20 { r.save(.newDefault(id: "a\(i)"), zone: prague) }
        #expect(r.save(.newDefault(id: "x"), zone: prague) == .tooManyAlarms)
    }

    @Test func skipNextAddsSkipOverride() throws {
        let clock = Clock("2026-10-19T12:00:00Z")   // Monday 14:00 Prague
        let r = repo(clock: clock)
        r.save(.newDefault(id: "a"), zone: prague)
        r.skipNext(id: "a", zone: prague)
        let s = try #require(r.alarm(id: "a"))
        #expect(s.overrides == [AlarmOverride(date: "2026-10-20", skip: true)])
        #expect(AlarmOccurrences.next(of: s, from: clock.now, zone: prague)?.localDate.description == "2026-10-21")
    }

    @Test func deleteQueuesDeleteAndAckClearsOutbox() throws {
        let clock = Clock("2026-10-19T12:00:00Z")
        let r = repo(clock: clock)
        r.save(.newDefault(id: "a"), zone: prague)
        r.delete(id: "a")
        #expect(r.alarms.isEmpty)
        let entry = try #require(r.document.outbox.first)
        #expect(entry.op == OutboxEntry.delete)
        r.acknowledge([entry])
        #expect(r.document.outbox.isEmpty)
    }

    @Test func corruptDocumentStartsEmpty() {
        #expect(repo(InMemoryDocumentStore(Data("{not json".utf8)), clock: Clock("2026-10-19T12:00:00Z")).alarms.isEmpty)
    }

    @Test func androidDocumentDecodes() throws {
        // Same JSON shape as Android's AlarmDocument (kotlinx.serialization with explicitNulls = false).
        let json = """
        {"schemaVersion":1,"alarms":[{"id":"a","version":2,"label":"x","enabled":true,"countsForChallenge":true,
        "kind":"weekly","weekly":{"mon":"06:30"},"overrides":[],"mode":{"type":"ringUntilDone","targetReps":20},
        "sound":{"id":"bundled.pulse"}}],"outbox":[],"active":[{"occurrenceId":"a:2026-10-19","alarmId":"a","label":"",
        "t0":"2026-10-19T04:30:00Z","rangAt":"2026-10-19T04:30:01Z","mode":{"type":"ringUntilDone","targetReps":20},
        "countsForChallenge":true,"practice":false,"snoozesUsed":0,"soundId":"bundled.pulse"}]}
        """
        let doc = try JSONDecoder().decode(AlarmDocument.self, from: Data(json.utf8))
        #expect(doc.alarms.first?.weekly?.mon == "06:30")
        #expect(doc.active.first?.target == 20)
    }
}

@Suite("Ring state")
struct RingStateTests {
    private func ring(_ mode: ChallengeMode, rangAt: String = "2026-10-20T04:30:00Z") -> RingState {
        RingState(occurrenceId: "a:2026-10-20", alarmId: "a", label: "", t0: "2026-10-20T04:30:00Z", rangAt: rangAt,
                  mode: mode, countsForChallenge: true)
    }

    @Test func escalationAddsRepsPerSnooze() {
        var r = ring(.defaults(for: .escalation, targetReps: 10))
        #expect(r.target == 10)
        for _ in 0..<3 {
            #expect(r.canSnooze)
            r = r.snoozed(at: r.t0Date)
        }
        #expect(r.target == 25)
        #expect(!r.canSnooze)
        #expect(r.snoozedUntil == "2026-10-20T04:35:00Z")
    }

    @Test func beatTheClockStartsAtLateRing() {
        let m = ChallengeMode(type: "beatTheClock", targetReps: 10, windowSeconds: 60)
        #expect(ring(m).beatTheClockEndsAt.map(ISOInstant.format) == "2026-10-20T04:31:00Z")
        #expect(ring(m, rangAt: "2026-10-20T04:30:20Z").beatTheClockEndsAt.map(ISOInstant.format) == "2026-10-20T04:31:20Z")
    }

    @Test func activeChainContinuesTheTwoMinuteGrid() throws {
        let r = ring(.default)
        let now = try #require(ISOInstant.parse("2026-10-20T04:33:10Z"))
        let chain = AlarmPlan.activeChain(for: r, now: now)
        #expect(chain.map(\.role) == ["nag2", "nag3", "nag4"])
        #expect(chain.first?.osAlarmID == AlarmPlan.osAlarmID(occurrenceID: "a:2026-10-20", role: "nag2"))
        let late = try #require(ISOInstant.parse("2026-10-20T04:57:00Z"))
        #expect(AlarmPlan.activeChain(for: r, now: late).map(\.role) == ["nag14"])
    }
}

@Suite("Health + diff")
struct HealthDiffTests {
    @Test func healthOrdering() {
        #expect(AlarmHealth.issues(HealthInput(hasEnabledAlarms: false, alarmKitAuthorized: false)).isEmpty)
        #expect(AlarmHealth.issues(HealthInput(hasEnabledAlarms: true, alarmKitAuthorized: false, nextAlarmArmed: false,
                                               alarmVolumeZero: true)) == [.alarmKitNotAuthorized, .alarmVolumeZero])
        #expect(AlarmHealth.issues(HealthInput(hasEnabledAlarms: true, alarmKitAuthorized: true, nextAlarmArmed: false))
                == [.nextAlarmNotArmed])
    }

    @Test func diffIsIdempotent() {
        let desired = [AlarmSyncDiff.Desired(key: "a", signature: "06:30", payload: 1),
                       AlarmSyncDiff.Desired(key: "b", signature: "07:00", payload: 2)]
        let first = AlarmSyncDiff.compute(desired: desired, current: ["a": "06:15", "z": "05:00"])
        #expect(first.cancel == ["a", "z"])
        #expect(first.schedule.map(\.key) == ["a", "b"])
        #expect(AlarmSyncDiff.compute(desired: desired, current: ["a": "06:30", "b": "07:00"]).isEmpty)
    }
}
