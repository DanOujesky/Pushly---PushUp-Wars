import SwiftUI
import WidgetKit

// Widget Extension target. Hosts the AlarmKit Live Activity (Phase 2, doc 04 §5.1)
// and the "Next alarm + streak" widget (Phase 6). Placeholder until then.

@main
struct PushlyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
    }
}

struct NextAlarmEntry: TimelineEntry {
    let date: Date
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry { NextAlarmEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(NextAlarmEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        completion(Timeline(entries: [NextAlarmEntry(date: .now)], policy: .never))
    }
}

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.pushly.next-alarm", provider: NextAlarmProvider()) { _ in
            Text("Pushly")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next alarm")
        .description("Your next wake-up and streak.")
        .supportedFamilies([.systemSmall])
    }
}
