import AlarmKit
import Foundation

/// Data attached to every Pushly AlarmKit alarm (doc 04 §5.1), shown by the Live Activity.
/// Compiled into both the app and the widget extension (project.yml: Shared/AlarmKit).
nonisolated struct PushlyAlarmMetadata: AlarmMetadata {
    var occurrenceID: String
    var alarmID: String
    var modeType: String
    var targetReps: Int
    var isNag: Bool
    var isPractice: Bool
}
