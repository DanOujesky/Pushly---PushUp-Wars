import AlarmDomain
import AlarmFeature
import BackgroundTasks
import Core
import Foundation
import UIKit

/// Builds the alarm system once per process: repository (App Group file), scheduler (only owner of AlarmKit),
/// Wake model, and the bridge from the alarm buttons (App Intents) into the app.
@MainActor
final class AlarmEnvironment {
    static let appGroup = "group.app.pushly"
    static let refreshTaskID = "app.pushly.alarm-refresh"

    let repository: AlarmRepository
    let scheduler: AlarmScheduler
    let model: WakeModel

    init(router: AppRouter) {
        AlarmLog.sink = { message in PLog.warning(message, .alarm) }
        let defaults = UserDefaults(suiteName: Self.appGroup) ?? .standard
        repository = AlarmRepository(store: FileDocumentStore(url: Self.documentURL()))
        scheduler = AlarmScheduler(repository: repository, client: AlarmKitClient(), defaults: defaults)
        model = WakeModel(scheduler: scheduler, reminder: HealthReminder())
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

    /// The alarm document lives in the App Group container (shared with the widget); falls back to Application Support
    /// when the container isn't available (unsigned simulator builds).
    static func documentURL() -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory())
        return base.appending(path: "Alarms/alarms.json")
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
