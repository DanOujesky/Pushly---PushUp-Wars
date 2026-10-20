import AlarmDomain
import Core
import Foundation

/// AlarmKit authorization, mirrored so the feature never imports AlarmKit itself.
public enum AlarmAuthState: Sendable, Equatable {
    case notDetermined, denied, authorized
}

/// One alarm the OS currently holds for us.
public struct OSAlarm: Sendable, Equatable {
    public let id: UUID
    public let isAlerting: Bool

    public init(id: UUID, isAlerting: Bool) {
        self.id = id
        self.isAlerting = isAlerting
    }
}

/// What an OS alarm shows and plays. Built from `IOSAlarmPlan.Item`.
public struct OSAlarmRequest: Sendable, Equatable {
    public let id: UUID
    public let occurrenceID: String
    public let alarmID: String
    public let fireAt: Date
    public let title: String
    public let soundFileName: String
    public let target: Int
    public let isNag: Bool
    public let isPractice: Bool
}

/// The raw OS alarm API (AlarmKit in the app target; a fake in tests). Only `AlarmScheduler` calls it (CLAUDE.md §10).
public protocol AlarmOSClient: Sendable {
    func authorizationState() -> AlarmAuthState
    func requestAuthorization() async -> AlarmAuthState
    func currentAlarms() throws -> [OSAlarm]
    func schedule(_ request: OSAlarmRequest) async throws
    func cancel(_ id: UUID) throws
    func stop(_ id: UUID) throws
}

/// Result of one `sync` (doc 04 §5.4).
public struct SyncReport: Sendable, Equatable {
    public var scheduled = 0
    public var cancelled = 0
    public var failed = 0
    public var desiredCount = 0
    /// True when the OS holds the earliest alarm we want armed (health check `nextAlarmNotArmed`).
    public var nextArmed = true

    public init() {}
}

/// A "Test my alarm" alarm (doc 04 §9), remembered until it fires.
struct PracticeAlarm: Codable, Hashable, Sendable {
    let osID: UUID
    let occurrenceID: String
    let alarmID: String
    let fireAt: Date
    let title: String
    let soundID: String
    let target: Int
}

/// The single owner of OS alarm state on iOS (doc 04 §5): computes the desired AlarmKit alarms from the repository
/// (rolling 7-day window, nag chains, snoozes, dead-man's switch, practice alarms) and diffs them against what the OS
/// holds. `sync` is idempotent: calling it twice changes nothing.
@MainActor
public final class AlarmScheduler {
    public let repository: AlarmRepository
    private let client: any AlarmOSClient
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let zone: @Sendable () -> TimeZone

    private enum Keys {
        static let signatures = "alarmkit.signatures"
        static let practice = "alarmkit.practice"
    }

    public private(set) var lastReport = SyncReport()

    public init(
        repository: AlarmRepository,
        client: any AlarmOSClient,
        defaults: UserDefaults,
        now: @escaping @Sendable () -> Date = { Date() },
        zone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.repository = repository
        self.client = client
        self.defaults = defaults
        self.now = now
        self.zone = zone
    }

    public var authorizationState: AlarmAuthState { client.authorizationState() }

    public func requestAuthorization() async -> AlarmAuthState {
        let state = await client.requestAuthorization()
        if state == .authorized { await sync() }
        return state
    }

    // MARK: Sync

    /// Makes the OS match the plan. Never throws: failures are logged and reported (health check).
    @discardableResult
    public func sync() async -> SyncReport {
        var report = SyncReport()
        let at = now()
        repository.pruneRings(at: at)
        // Practice alarms are remembered until their deadline so "Start push-ups" still finds them after they rang.
        let practice = practiceAlarms().filter { $0.fireAt.addingTimeInterval(AlarmOccurrences.deadline) > at }
        savePractice(practice)

        let desiredItems = IOSAlarmPlan.desired(
            schedules: repository.alarms,
            active: repository.activeRings,
            finished: repository.document.finished,
            practice: practice.map(Self.item),
            now: at,
            zone: zone()
        )
        report.desiredCount = desiredItems.count
        guard client.authorizationState() == .authorized else {
            report.nextArmed = desiredItems.isEmpty
            lastReport = report
            return report
        }

        let osAlarms: [OSAlarm]
        do {
            osAlarms = try client.currentAlarms()
        } catch {
            PLog.error("AlarmKit alarms unreadable: \(error)", .alarm)
            report.failed += 1
            report.nextArmed = false
            lastReport = report
            return report
        }

        var signatures = storedSignatures()
        // What the OS has armed, with the signature we recorded when scheduling it ("?" = unknown → re-schedule).
        let current = Dictionary(
            osAlarms.filter { !$0.isAlerting }.map { ($0.id.uuidString, signatures[$0.id.uuidString] ?? "?") },
            uniquingKeysWith: { a, _ in a }
        )
        let desired = desiredItems.map {
            AlarmSyncDiff.Desired(key: $0.alarm.osAlarmID.uuidString, signature: $0.signature, payload: $0)
        }
        let diff = AlarmSyncDiff.compute(desired: desired, current: current)

        for key in diff.cancel {
            guard let id = UUID(uuidString: key) else { continue }
            do {
                try client.cancel(id)
                report.cancelled += 1
            } catch {
                PLog.warning("Cancel failed for \(key): \(error)", .alarm)
            }
            signatures[key] = nil
        }
        let practiceIDs = Set(practice.map(\.osID))
        for d in diff.schedule {
            let item = d.payload
            do {
                try await client.schedule(Self.request(item, practice: practiceIDs.contains(item.alarm.osAlarmID)))
                signatures[d.key] = d.signature
                report.scheduled += 1
            } catch {
                PLog.error("Scheduling \(item.alarm.role) for \(item.alarm.occurrenceID) failed: \(error)", .alarm)
                report.failed += 1
            }
        }
        // Forget records of alarms the OS no longer has (fired or removed by the user).
        let live = Set(osAlarms.map(\.id.uuidString)).union(diff.schedule.map(\.key))
        signatures = signatures.filter { live.contains($0.key) }
        storeSignatures(signatures)

        if let first = desiredItems.first {
            let armed = live.contains(first.alarm.osAlarmID.uuidString) && signatures[first.alarm.osAlarmID.uuidString] != nil
            report.nextArmed = armed
        }
        if report.scheduled + report.cancelled > 0 {
            PLog.info("Alarm sync: +\(report.scheduled) −\(report.cancelled), \(report.failed) failed", .alarm)
        }
        lastReport = report
        return report
    }

    /// Repairs state after missed callbacks (doc 04 §5.2 quirk): alarms stuck alerting for > 2 min are stopped, then
    /// the plan is re-applied (which also restores nag chains of occurrences still within their deadline).
    @discardableResult
    public func reconcile() async -> SyncReport {
        if client.authorizationState() == .authorized, let alarms = try? client.currentAlarms() {
            let signatures = storedSignatures()
            let at = now()
            for alarm in alarms where alarm.isAlerting {
                let firedAt = signatures[alarm.id.uuidString].flatMap(Self.fireDate(fromSignature:))
                if let firedAt, at.timeIntervalSince(firedAt) > 120 {
                    try? client.stop(alarm.id)
                    PLog.warning("Stopped alarm stuck alerting since \(firedAt)", .alarm)
                }
            }
        }
        return await sync()
    }

    // MARK: Ring lifecycle

    /// The user opened the wake session (Start push-ups / in-app). Arms the dead-man's switch nag.
    public func sessionStarted(_ ring: RingState) async {
        var state = ring
        state.deadManAt = ISOInstant.format(now().addingTimeInterval(IOSAlarmPlan.deadManDelay))
        repository.putRing(state)
        stopAlerting(occurrenceID: ring.occurrenceId)
        await sync()
    }

    /// Called every minute while the wake session is open: pushes the dead-man nag 90 s into the future.
    public func sessionHeartbeat(occurrenceID: String) async {
        guard var state = repository.activeRings.first(where: { $0.occurrenceId == occurrenceID }) else { return }
        state.deadManAt = ISOInstant.format(now().addingTimeInterval(IOSAlarmPlan.deadManDelay))
        repository.putRing(state)
        await sync()
    }

    /// The user left the session without finishing: the nag chain keeps ringing, the dead-man nag is dropped.
    public func sessionLeft(occurrenceID: String) async {
        guard var state = repository.activeRings.first(where: { $0.occurrenceId == occurrenceID }) else { return }
        state.deadManAt = nil
        repository.putRing(state)
        await sync()
    }

    /// Push-ups done or given up: cancel every remaining nag of the occurrence immediately (AT-ALM-06).
    public func finish(occurrenceID: String) async {
        repository.finish(occurrenceId: occurrenceID)
        stopAlerting(occurrenceID: occurrenceID)
        removePractice(occurrenceID: occurrenceID)
        await sync()
    }

    /// Escalation snooze (doc 04 §3): one alarm at the end of the snooze instead of the nag chain.
    public func snooze(occurrenceID: String) async -> RingState? {
        guard let state = repository.activeRings.first(where: { $0.occurrenceId == occurrenceID }), state.canSnooze else {
            return nil
        }
        var snoozed = state.snoozed(at: now())
        snoozed.deadManAt = nil
        repository.putRing(snoozed)
        stopAlerting(occurrenceID: occurrenceID)
        await sync()
        return snoozed
    }

    /// The alarm's Stop button was pressed (AlarmStoppedIntent): record that it rang; nags keep going.
    public func stopPressed(occurrenceID: String, alarmID: String) async {
        if repository.activeRings.first(where: { $0.occurrenceId == occurrenceID }) == nil,
           let ring = ringState(occurrenceID: occurrenceID, alarmID: alarmID) {
            repository.putRing(ring)
        }
        await sync()
    }

    /// Ring state for an occurrence the OS rang (or a practice alarm), from the current schedule.
    public func ringState(occurrenceID: String, alarmID: String) -> RingState? {
        if let existing = repository.activeRings.first(where: { $0.occurrenceId == occurrenceID }) { return existing }
        let schedule = repository.alarm(id: alarmID)
        if let p = practiceAlarms().first(where: { $0.occurrenceID == occurrenceID }) {
            let base = schedule ?? AlarmSchedule.newDefault(id: alarmID)
            let occ = Occurrence(occurrenceID: p.occurrenceID, alarmID: alarmID, localDate: LocalDate(instant: p.fireAt, zone: zone()),
                                 instant: p.fireAt, countsForChallenge: false)
            return RingState.start(occ, schedule: base, rangAt: now(), practice: true)
        }
        guard let schedule else { return nil }
        let at = now()
        let recent = AlarmOccurrences.occurrences(of: schedule, from: at.addingTimeInterval(-AlarmOccurrences.deadline),
                                                  zone: zone(), horizonDays: 1)
        guard let occ = recent.first(where: { $0.occurrenceID == occurrenceID }) else { return nil }
        return RingState.start(occ, schedule: schedule, rangAt: occ.instant)
    }

    /// The occurrence the user should be doing push-ups for right now, if any (Wake tab "ringing" card).
    public func liveRing() -> RingState? {
        let at = now()
        let finished = Set(repository.document.finished)
        if let active = repository.activeRings
            .filter({ !$0.isExpired(at: at) && !finished.contains($0.occurrenceId) && $0.t0Date <= at })
            .min(by: { $0.t0Date < $1.t0Date }) {
            return active
        }
        let enabled = repository.alarms.filter(\.enabled)
        let recent = AlarmOccurrences.all(enabled, from: at.addingTimeInterval(-AlarmOccurrences.deadline), zone: zone(), horizonDays: 1)
        for date in Set(recent.map(\.localDate)).sorted() {
            guard let c = AlarmOccurrences.challengeOccurrence(on: date, in: recent), c.instant <= at,
                  !finished.contains(c.occurrenceID), let s = repository.alarm(id: c.alarmID) else { continue }
            return RingState.start(c, schedule: s, rangAt: c.instant)
        }
        return nil
    }

    // MARK: Practice ("Test my alarm", doc 04 §9)

    /// Arms a practice alarm in `delay` seconds with the alarm's settings. Returns false if alarms aren't allowed.
    @discardableResult
    public func armPractice(_ schedule: AlarmSchedule, delay: TimeInterval = 10) async -> Bool {
        guard client.authorizationState() == .authorized else { return false }
        let osID = UUID()
        let p = PracticeAlarm(osID: osID, occurrenceID: "practice:\(osID.uuidString.lowercased())", alarmID: schedule.id,
                              fireAt: now().addingTimeInterval(delay), title: schedule.label, soundID: schedule.sound.id,
                              target: schedule.mode.totalReps)
        savePractice(practiceAlarms() + [p])
        let report = await sync()
        return report.failed == 0
    }

    // MARK: Helpers

    private func stopAlerting(occurrenceID: String) {
        guard client.authorizationState() == .authorized, let alarms = try? client.currentAlarms() else { return }
        let signatures = storedSignatures()
        let ids = Set(["main", "nag1", "nag2", "nag3", "deadman", "practice"].map {
            AlarmPlan.osAlarmID(occurrenceID: occurrenceID, role: $0).uuidString
        })
        for alarm in alarms where alarm.isAlerting {
            let key = alarm.id.uuidString
            // Our own ids for this occurrence, or any alerting alarm we scheduled (only one occurrence rings at a time).
            if ids.contains(key) || signatures[key] != nil { try? client.stop(alarm.id) }
        }
    }

    private static func item(_ p: PracticeAlarm) -> IOSAlarmPlan.Item {
        let planned = PlannedAlarm(osAlarmID: p.osID, occurrenceID: p.occurrenceID, alarmID: p.alarmID, role: "practice",
                                   fireAt: p.fireAt, countsForChallenge: false)
        return IOSAlarmPlan.Item(alarm: planned, title: p.title, soundID: p.soundID, target: p.target)
    }

    static func request(_ item: IOSAlarmPlan.Item, practice: Bool) -> OSAlarmRequest {
        OSAlarmRequest(
            id: item.alarm.osAlarmID,
            occurrenceID: item.alarm.occurrenceID,
            alarmID: item.alarm.alarmID,
            fireAt: item.alarm.fireAt,
            title: item.title,
            soundFileName: AlarmSounds.resourceName(item.soundID) + ".wav",
            target: item.target,
            isNag: item.alarm.isNag && !practice,
            isPractice: practice
        )
    }

    /// Signatures start with the fire time in epoch seconds (`IOSAlarmPlan.Item.signature`).
    static func fireDate(fromSignature s: String) -> Date? {
        s.split(separator: "|").first.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
    }

    private func storedSignatures() -> [String: String] {
        defaults.dictionary(forKey: Keys.signatures) as? [String: String] ?? [:]
    }

    private func storeSignatures(_ s: [String: String]) {
        defaults.set(s, forKey: Keys.signatures)
    }

    private func practiceAlarms() -> [PracticeAlarm] {
        defaults.data(forKey: Keys.practice).flatMap { try? JSONDecoder().decode([PracticeAlarm].self, from: $0) } ?? []
    }

    private func savePractice(_ list: [PracticeAlarm]) {
        defaults.set(try? JSONEncoder().encode(list), forKey: Keys.practice)
    }

    private func removePractice(occurrenceID: String) {
        savePractice(practiceAlarms().filter { $0.occurrenceID != occurrenceID })
    }
}
