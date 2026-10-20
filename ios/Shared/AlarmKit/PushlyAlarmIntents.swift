import AlarmKit
import AppIntents
import Foundation

/// Hands alarm button presses to the app (set by the app at launch; nil inside the widget extension).
/// Events that arrive before the app is ready are queued.
@MainActor
enum PushlyAlarmEvents {
    enum Kind: Sendable { case start, stopped }

    struct Event: Sendable {
        let kind: Kind
        let occurrenceID: String
        let alarmID: String
    }

    static var handler: ((Event) -> Void)? {
        didSet {
            guard let handler else { return }
            let queued = pending
            pending = []
            queued.forEach(handler)
        }
    }

    private static var pending: [Event] = []

    static func post(_ event: Event) {
        if let handler { handler(event) } else { pending.append(event) }
    }
}

/// Secondary button "Start push-ups": opens the app straight into the wake session (doc 04 §5.1).
struct StartWakeSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start push-ups"
    static let description = IntentDescription("Opens Pushly to do your wake-up push-ups.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Alarm") var osAlarmID: String
    @Parameter(title: "Occurrence") var occurrenceID: String
    @Parameter(title: "Alarm schedule") var alarmID: String

    init() {}

    init(osAlarmID: UUID, occurrenceID: String, alarmID: String) {
        self.osAlarmID = osAlarmID.uuidString
        self.occurrenceID = occurrenceID
        self.alarmID = alarmID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: osAlarmID) { try? AlarmManager.shared.stop(id: id) }
        PushlyAlarmEvents.post(.init(kind: .start, occurrenceID: occurrenceID, alarmID: alarmID))
        return .result()
    }
}

/// The required Stop button. Stopping never ends the challenge: the nag chain keeps ringing (doc 04 §5.2).
struct AlarmStoppedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop"
    static let description = IntentDescription("Stops the ringing. The challenge continues until your push-ups are done.")
    static let isDiscoverable = false

    @Parameter(title: "Alarm") var osAlarmID: String
    @Parameter(title: "Occurrence") var occurrenceID: String
    @Parameter(title: "Alarm schedule") var alarmID: String

    init() {}

    init(osAlarmID: UUID, occurrenceID: String, alarmID: String) {
        self.osAlarmID = osAlarmID.uuidString
        self.occurrenceID = occurrenceID
        self.alarmID = alarmID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: osAlarmID) { try? AlarmManager.shared.stop(id: id) }
        PushlyAlarmEvents.post(.init(kind: .stopped, occurrenceID: occurrenceID, alarmID: alarmID))
        return .result()
    }
}
