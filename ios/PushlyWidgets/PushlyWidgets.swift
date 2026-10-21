import AlarmDomain
import DesignSystem
import SwiftUI
import WidgetKit

// Widget Extension target. Hosts the AlarmKit Live Activity (doc 04 §5.1, AlarmLiveActivity.swift)
// and the "Next alarm + streak" widget (P6-07) on the home and lock screen.

@main
struct PushlyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        AlarmLiveActivity()
    }
}

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the snapshot the app writes into the App Group (no network here). One entry now and one right after each
/// upcoming ring, so the widget moves on to the following alarm by itself.
struct NextAlarmProvider: TimelineProvider {
    static let appGroup = "group.app.pushly"

    static func load() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: WidgetSnapshot.fileName),
            let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, snapshot: WidgetSnapshot(
            upcoming: [.init(at: .now.addingTimeInterval(8 * 3600), label: "", targetReps: 20, countsForChallenge: true)],
            streak: 12, repsToday: 40, today: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : NextAlarmEntry(date: .now, snapshot: Self.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let snapshot = Self.load()
        let now = Date.now
        var entries = [NextAlarmEntry(date: now, snapshot: snapshot)]
        for ring in snapshot?.upcoming ?? [] where ring.at > now {
            entries.append(NextAlarmEntry(date: ring.at.addingTimeInterval(1), snapshot: snapshot))
        }
        // Midnight resets "push-ups today".
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            entries.append(NextAlarmEntry(date: midnight, snapshot: snapshot))
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.pushly.next-alarm", provider: NextAlarmProvider()) { entry in
            NextAlarmView(entry: entry)
                .containerBackground(for: .widget) { Color(ColorTokens.bgBase) }
                .widgetURL(URL(string: "pushly://wake"))
        }
        .configurationDisplayName("Next alarm")
        .description("Your next wake-up challenge and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextAlarmView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAlarmEntry

    private var ring: WidgetSnapshot.Upcoming? { entry.snapshot?.next(after: entry.date) }
    private var streak: Int { entry.snapshot?.streak ?? 0 }
    private var repsToday: Int? { entry.snapshot?.repsToday(at: entry.date, zone: .current) }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private func time(_ date: Date) -> Text {
        Text(date, format: .dateTime.hour().minute())
    }

    private func day(_ date: Date) -> Text {
        Calendar.current.isDateInToday(date) ? Text("Today")
            : Calendar.current.isDateInTomorrow(date) ? Text("Tomorrow")
            : Text(date, format: .dateTime.weekday(.wide))
    }

    @ViewBuilder
    private var inline: some View {
        if let ring {
            Text("⏰ \(time(ring.at)) · 🔥 \(streak)")
        } else {
            Text("🔥 \(streak) · No alarm set")
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: "alarm.fill").accessibilityHidden(true)
            if let ring { time(ring.at).font(.caption2.weight(.bold)) } else { Text(verbatim: "–") }
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ring {
                HStack(spacing: 4) {
                    Image(systemName: "alarm.fill").accessibilityHidden(true)
                    time(ring.at).font(.headline)
                    day(ring.at).font(.caption)
                }
                Text(ring.targetReps.map { "\($0) push-ups" } ?? "Push-up alarm").font(.caption)
            } else {
                Text("No alarm set").font(.headline)
            }
            Text("🔥 \(streak) day streak").font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("NEXT ALARM")
                .typography(TypographyTokens.overline)
                .foregroundStyle(Color(ColorTokens.brandFlameText))
            if let ring {
                time(ring.at)
                    .typography(TypographyTokens.displayM)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .minimumScaleFactor(0.6)
                day(ring.at)
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                if let target = ring.targetReps {
                    Text("\(target) push-ups")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                }
            } else {
                Text("No alarm set")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
            }
            Spacer(minLength: 0)
            Text(verbatim: "🔥 \(streak)")
                .typography(TypographyTokens.labelDisplay)
                .foregroundStyle(Color(streak > 0 ? ColorTokens.brandFlameText : ColorTokens.textTertiary))
                .accessibilityLabel(Text("\(streak) day wake streak"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: SpacingTokens.l) {
            small
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text("TODAY")
                    .typography(TypographyTokens.overline)
                    .foregroundStyle(Color(ColorTokens.brandVoltText))
                Text(verbatim: "\(repsToday ?? 0)")
                    .typography(TypographyTokens.displayM)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text("push-ups")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
