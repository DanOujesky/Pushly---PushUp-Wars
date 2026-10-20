import AlarmDomain
import AlarmFeature
import BackgroundTasks
import Core
import Foundation
import Networking
import UIKit
import WakeFlowFeature

/// Builds the alarm system once per process: repository (App Group file), scheduler (only owner of AlarmKit),
/// Wake model, and the bridge from the alarm buttons (App Intents) into the app.
@MainActor
final class AlarmEnvironment {
    static let appGroup = "group.app.pushly"
    static let refreshTaskID = "app.pushly.alarm-refresh"

    let repository: AlarmRepository
    let scheduler: AlarmScheduler
    let model: WakeModel

    init(router: AppRouter, session: AppSession) {
        AlarmLog.sink = { message in PLog.warning(message, .alarm) }
        let defaults = UserDefaults(suiteName: Self.appGroup) ?? .standard
        repository = AlarmRepository(store: FileDocumentStore(url: Self.documentURL()))
        scheduler = AlarmScheduler(repository: repository, client: AlarmKitClient(), defaults: defaults)
        let repository = repository
        let sync = AlarmSyncCoordinator(repository: repository) { [weak session] in
            guard let session, let backend = session.alarmSync, let auth = session.auth,
                  await auth.currentUserID() != nil else { return nil }
            return { data in try await backend.syncAlarms(data) }
        }
        model = WakeModel(scheduler: scheduler, reminder: HealthReminder(), sync: sync,
                          services: Self.sessionServices(session: session))
        let model = model
        PushlyAlarmEvents.handler = { event in
            if event.kind == .start { router.selectedTab = .wake }
            Task {
                switch event.kind {
                case .start: await model.handle(.start(occurrenceID: event.occurrenceID, alarmID: event.alarmID))
                case .stopped: await model.handle(.stopped(occurrenceID: event.occurrenceID, alarmID: event.alarmID))
                }
            }
        }
        observeTimeChanges()
    }

    /// Rep-log outbox (Application Support/RepSessions) + server clock + Wake summary. Uploads only while signed in;
    /// sessions are queued offline and in guest mode (doc 03 §5, PS-34).
    static func sessionServices(session: AppSession) -> SessionServices {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        // Signed envelopes with this install's key (D-047); the key is registered once per launch.
        var signer: LogSigner?
        if let backend = session.repSessions {
            let register: LogSigner.Register = { request in try await backend.registerDevice(request) }
            signer = LogSigner(key: DeviceKey.loadOrCreate(), appVersion: "\(version) (\(build))", register: register)
        }
        let logSigner = signer
        let uploader = SessionUploader(directory: base.appending(path: "RepSessions")) { [weak session] in
            guard let session, let backend = session.repSessions, let auth = session.auth,
                  await auth.currentUserID() != nil else { return nil }
            return { data in
                var body = data
                if let logSigner { body = await logSigner.envelope(data) }
                return try await backend.submitRepSession(body)
            }
        }
        var fetchServerMs: (@Sendable () async throws -> Int64)?
        var summary: (@Sendable () async throws -> Data)?
        if let backend = session.repSessions {
            fetchServerMs = { try await backend.serverTimeMs() }
            summary = { try await backend.wakeSummary() }
        }
        return SessionServices(uploader: uploader, appVersion: "\(version) (\(build))", fetchServerMs: fetchServerMs,
                               summary: summary)
    }

    /// The alarm document lives in the App Group container (shared with the widget); falls back to Application Support
    /// when the container isn't available (unsigned simulator builds).
    static func documentURL() -> URL {
        let fm = FileManager.default
        let fallback = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(filePath: NSTemporaryDirectory()))
            .appending(path: "Alarms/alarms.json")
        guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return fallback }
        let url = group.appending(path: "Alarms/alarms.json")
        // A build signed without the App Group kept alarms in Application Support: move them over once.
        if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: fallback.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: fallback, to: url)
        }
        return url
    }

    /// Re-fill the rolling window when the clock or time zone changes (doc 04 §5.3).
    private func observeTimeChanges() {
        let names: [Notification.Name] = [UIApplication.significantTimeChangeNotification, .NSSystemTimeZoneDidChange]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.model.refresh() }
                }
            }
        }
    }

    /// Daily background refresh keeps the 7-day window full even if the app isn't opened (doc 04 §5.3).
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(12 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            PLog.warning("Background refresh not scheduled: \(error)", .alarm)
        }
    }

    func backgroundRefresh() async {
        Self.scheduleBackgroundRefresh()
        await model.refresh()
    }
}

#if DEBUG
extension AlarmEnvironment {
    /// Debug builds only: sample alarms / a practice wake session for the CI screenshot step (ios.yml).
    func applyDebugScreen() async {
        guard let screen = UserDefaults.standard.string(forKey: "PushlyDebugScreen") else { return }
        guard ["wake", "wakeSession"].contains(screen) else { return }
        if repository.alarms.isEmpty {
            var weekday = AlarmSchedule(id: "d0000000-0000-4000-8000-000000000001", label: "Get up, champion",
                                        weekly: WeeklyTimes(mon: "06:30", tue: "06:30", wed: "06:30", thu: "06:30", fri: "06:30"))
            weekday.mode = .default
            var weekend = AlarmSchedule(id: "d0000000-0000-4000-8000-000000000002", label: "Weekend",
                                        weekly: WeeklyTimes(sat: "09:00", sun: "09:30"))
            weekend.mode = ChallengeMode.defaults(for: .escalation, targetReps: 15)
            weekend.sound = AlarmSound(id: "bundled.arena")
            repository.save(weekday)
            repository.save(weekend)
        }
        if screen == "wakeSession", let alarm = repository.alarms.first {
            let now = Date()
            let occ = Occurrence(occurrenceID: "practice:debug", alarmID: alarm.id, localDate: LocalDate(instant: now, zone: .current),
                                 instant: now, countsForChallenge: false)
            model.session = RingState.start(occ, schedule: alarm, rangAt: now, practice: true)
        }
    }
}
#endif
