import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// Live Activity for Pushly alarms (doc 04 §5.1): Lock Screen and Dynamic Island while an alarm is pending or alerting.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PushlyAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Pushly")
                        .font(.headline)
                    Text(Self.subtitle(context.attributes.metadata))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(Self.subtitle(context.attributes.metadata))
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                Text(verbatim: "\(context.attributes.metadata?.targetReps ?? 0)")
                    .font(.caption.weight(.bold))
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    static func subtitle(_ m: PushlyAlarmMetadata?) -> LocalizedStringKey {
        guard let m else { return "Wake-up alarm" }
        if m.isPractice { return "Practice alarm" }
        return "\(m.targetReps) push-ups to stop it"
    }
}
