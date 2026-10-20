import AlarmFeature
import ActivityKit
import AlarmKit
import Core
import SwiftUI

/// The only place that talks to AlarmKit (CLAUDE.md §10: through `AlarmScheduler`, which owns this client).
struct AlarmKitClient: AlarmOSClient {
    func authorizationState() -> AlarmAuthState {
        Self.map(AlarmManager.shared.authorizationState)
    }

    func requestAuthorization() async -> AlarmAuthState {
        do {
            return Self.map(try await AlarmManager.shared.requestAuthorization())
        } catch {
            PLog.error("AlarmKit authorization failed: \(error)", .alarm)
            return authorizationState()
        }
    }

    func currentAlarms() throws -> [OSAlarm] {
        try AlarmManager.shared.alarms.map { OSAlarm(id: $0.id, isAlerting: $0.state == .alerting) }
    }

    func schedule(_ r: OSAlarmRequest) async throws {
        let title: LocalizedStringResource = r.isNag
            ? "Still in bed? \(r.target) push-ups waiting"
            : r.isPractice ? "Practice alarm" : (r.title.isEmpty ? "Time to wake up" : "\(r.title)")
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "Start push-ups", textColor: .white, systemImageName: "figure.strengthtraining.functional"),
            secondaryButtonBehavior: .custom
        )
        let metadata = PushlyAlarmMetadata(occurrenceID: r.occurrenceID, alarmID: r.alarmID, modeType: "", targetReps: r.target,
                                           isNag: r.isNag, isPractice: r.isPractice)
        let attributes = AlarmAttributes<PushlyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: Color(red: 1, green: 0x5A / 255, blue: 0x1F / 255) // brand.flame — identifies Pushly alarms
        )
        let configuration = AlarmManager.AlarmConfiguration<PushlyAlarmMetadata>(
            schedule: .fixed(r.fireAt),
            attributes: attributes,
            stopIntent: AlarmStoppedIntent(osAlarmID: r.id, occurrenceID: r.occurrenceID, alarmID: r.alarmID),
            secondaryIntent: StartWakeSessionIntent(osAlarmID: r.id, occurrenceID: r.occurrenceID, alarmID: r.alarmID),
            sound: .named(r.soundFileName)
        )
        _ = try await AlarmManager.shared.schedule(id: r.id, configuration: configuration)
    }

    func cancel(_ id: UUID) throws {
        try AlarmManager.shared.cancel(id: id)
    }

    func stop(_ id: UUID) throws {
        try AlarmManager.shared.stop(id: id)
    }

    private static func map(_ s: AlarmManager.AuthorizationState) -> AlarmAuthState {
        switch s {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}
