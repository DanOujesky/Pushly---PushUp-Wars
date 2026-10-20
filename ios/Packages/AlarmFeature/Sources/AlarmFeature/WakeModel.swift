import AlarmDomain
import AVFoundation
import Core
import Foundation
import Observation

/// Events coming from the system alarm UI (App Intents in the app target).
public enum AlarmEvent: Sendable, Equatable {
    /// "Start push-ups" on the alarm (secondary button): open the wake session.
    case start(occurrenceID: String, alarmID: String)
    /// "Stop" on the alarm: the alarm rang; nags keep going until the push-ups are done.
    case stopped(occurrenceID: String, alarmID: String)
}

/// Wake tab + editor + wake session state (doc 02 PS-20…26). All alarm writes go through the repository, then the
/// scheduler re-syncs. Mirrors Android `WakeViewModel`.
@MainActor
@Observable
public final class WakeModel {
    public struct Item: Identifiable, Equatable {
        public let schedule: AlarmSchedule
        public let next: Occurrence?
        public let skippedDate: String?
        public var id: String { schedule.id }
    }

    public enum Notice: Equatable {
        case testArmed, testFailed
    }

    public let scheduler: AlarmScheduler
    public private(set) var items: [Item] = []
    public private(set) var next: Occurrence?
    public private(set) var health: [HealthIssue] = []
    public private(set) var live: RingState?
    public private(set) var now: Date
    public var notice: Notice?
    /// The wake session being shown full screen (Start push-ups).
    public var session: RingState?
    public private(set) var authorization: AlarmAuthState

    private let clock: @Sendable () -> Date
    private let cameraDenied: @Sendable () -> Bool
    private let reminder: HealthReminder?
    private let sync: AlarmSyncCoordinator?

    public var repository: AlarmRepository { scheduler.repository }

    public init(
        scheduler: AlarmScheduler,
        clock: @escaping @Sendable () -> Date = { Date() },
        cameraDenied: @escaping @Sendable () -> Bool = WakeModel.systemCameraDenied,
        reminder: HealthReminder? = nil,
        sync: AlarmSyncCoordinator? = nil
    ) {
        self.scheduler = scheduler
        self.clock = clock
        self.cameraDenied = cameraDenied
        self.reminder = reminder
        self.sync = sync
        now = clock()
        authorization = scheduler.authorizationState
        recompute()
    }

    public nonisolated static func systemCameraDenied() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    // MARK: Refresh

    /// Re-reads OS state (launch, foreground, every minute) and repairs the schedule (doc 04 §5.3, §8).
    public func refresh() async {
        // Server sync first (restores alarms on a new phone); the OS schedule always comes from local data.
        await sync?.syncIfNeeded()
        let report = await scheduler.reconcile()
        authorization = scheduler.authorizationState
        recompute(report: report)
    }

    /// Cheap UI tick (countdowns, "in 7 h 12 min").
    public func tick() {
        recompute(report: scheduler.lastReport)
    }

    private func recompute(report: SyncReport? = nil) {
        now = clock()
        let zone = TimeZone.current
        let today = LocalDate(instant: now, zone: zone).description
        items = repository.alarms.map { s in
            let next = s.enabled ? AlarmOccurrences.next(of: s, from: now, zone: zone) : nil
            let skipped = s.overrides.filter { $0.skip == true && $0.date >= today }.map(\.date).min()
            return Item(schedule: s, next: next, skippedDate: skipped)
        }
        next = items.compactMap(\.next).min { $0.instant < $1.instant }
        live = scheduler.liveRing()
        let hasEnabled = repository.alarms.contains(where: \.enabled)
        let input = HealthInput(
            hasEnabledAlarms: hasEnabled,
            alarmKitAuthorized: authorization == .authorized,
            cameraDenied: cameraDenied(),
            nextAlarmArmed: report.map(\.nextArmed)
        )
        health = AlarmHealth.issues(input)
        reminder?.update(critical: health.contains { $0.severity == .critical }, nextAlarm: next?.instant, now: now)
    }

    // MARK: Editing

    public func newSchedule() -> AlarmSchedule { AlarmSchedule.newDefault(id: UUID().uuidString.lowercased()) }

    public var canAddAlarm: Bool { repository.alarms.count < AlarmSchedule.maxAlarmsPerUser }

    /// Whether the permission explainer must be shown (after the first alarm is saved — never at launch).
    public var needsPermission: Bool { authorization != .authorized }

    @discardableResult
    public func save(_ schedule: AlarmSchedule) async -> SaveResult {
        let result = repository.save(schedule)
        if case .saved = result { await refresh() }
        return result
    }

    public func delete(id: String) async {
        repository.delete(id: id)
        await refresh()
    }

    public func setEnabled(id: String, _ enabled: Bool) async {
        repository.setEnabled(id: id, enabled)
        await refresh()
    }

    public func skipNext(id: String) async {
        repository.skipNext(id: id)
        await refresh()
    }

    public func undoSkip(id: String, date: String) async {
        repository.unskip(id: id, date: date)
        await refresh()
    }

    public func testAlarm(_ schedule: AlarmSchedule) async {
        notice = await scheduler.armPractice(schedule) ? .testArmed : .testFailed
    }

    public func requestAuthorization() async -> AlarmAuthState {
        authorization = await scheduler.requestAuthorization()
        await refresh()
        return authorization
    }

    // MARK: Ringing / wake session

    public func handle(_ event: AlarmEvent) async {
        switch event {
        case let .start(occurrenceID, alarmID):
            if let ring = scheduler.ringState(occurrenceID: occurrenceID, alarmID: alarmID) {
                await startSession(ring)
            } else {
                PLog.warning("Start intent for unknown occurrence \(occurrenceID)", .alarm)
                await refresh()
            }
        case let .stopped(occurrenceID, alarmID):
            await scheduler.stopPressed(occurrenceID: occurrenceID, alarmID: alarmID)
            recompute(report: scheduler.lastReport)
        }
    }

    public func startSession(_ ring: RingState) async {
        await scheduler.sessionStarted(ring)
        session = repository.activeRings.first { $0.occurrenceId == ring.occurrenceId } ?? ring
        recompute(report: scheduler.lastReport)
    }

    public func heartbeat() async {
        guard let session else { return }
        await scheduler.sessionHeartbeat(occurrenceID: session.occurrenceId)
    }

    /// Back to the alarm without finishing: the occurrence keeps nagging.
    public func leaveSession() async {
        guard let s = session else { return }
        session = nil
        await scheduler.sessionLeft(occurrenceID: s.occurrenceId)
        recompute(report: scheduler.lastReport)
    }

    /// Push-ups done. In Phase 2 only the debug build can call this (camera arrives in Phase 3).
    public func completeSession() async {
        guard let s = session else { return }
        session = nil
        await scheduler.finish(occurrenceID: s.occurrenceId)
        PLog.info("Wake session completed (provisional): \(s.occurrenceId)", .alarm)
        recompute(report: scheduler.lastReport)
    }

    public func giveUp() async {
        let target = session ?? live
        guard let s = target else { return }
        session = nil
        await scheduler.finish(occurrenceID: s.occurrenceId)
        PLog.info("Wake challenge given up: \(s.occurrenceId)", .alarm)
        recompute(report: scheduler.lastReport)
    }

    public func snooze() async {
        guard let s = session else { return }
        session = nil
        _ = await scheduler.snooze(occurrenceID: s.occurrenceId)
        recompute(report: scheduler.lastReport)
    }
}
