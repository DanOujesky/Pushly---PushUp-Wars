import Foundation

/// What the home / lock screen widgets show (P6-07): written by the app into the App Group container, read by the
/// widget extension. Only local data the app already has — no network in the widget. Same fields on Android.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Upcoming: Codable, Hashable, Sendable {
        public var at: Date
        public var label: String
        public var targetReps: Int?
        public var countsForChallenge: Bool

        public init(at: Date, label: String, targetReps: Int?, countsForChallenge: Bool) {
            self.at = at
            self.label = label
            self.targetReps = targetReps
            self.countsForChallenge = countsForChallenge
        }
    }

    /// Next rings (all alarms, soonest first, at most 8 within the next 7 days).
    public var upcoming: [Upcoming]
    /// Current wake streak from the last server summary (nil = unknown / signed out).
    public var streak: Int?
    /// Push-ups today and the local date they belong to (YYYY-MM-DD).
    public var repsToday: Int?
    public var today: String?

    public init(upcoming: [Upcoming], streak: Int?, repsToday: Int?, today: String?) {
        self.upcoming = upcoming
        self.streak = streak
        self.repsToday = repsToday
        self.today = today
    }

    public static let fileName = "widget-snapshot.json"
    public static let maxUpcoming = 8

    /// Builds the upcoming list from the local schedules (same occurrence rules as the alarms themselves).
    public static func upcoming(_ schedules: [AlarmSchedule], from now: Date, zone: TimeZone) -> [Upcoming] {
        let byId = Dictionary(schedules.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return AlarmOccurrences.all(schedules.filter(\.enabled), from: now, zone: zone, horizonDays: 7)
            .filter { $0.instant > now }
            .sorted { $0.instant < $1.instant }
            .prefix(maxUpcoming)
            .map { o in
                let s = byId[o.alarmID]
                return Upcoming(at: o.instant, label: s?.label ?? "", targetReps: s?.mode.targetReps,
                                countsForChallenge: o.countsForChallenge)
            }
    }

    /// The ring to show at `date` (the first one still ahead).
    public func next(after date: Date) -> Upcoming? { upcoming.first { $0.at > date } }

    /// Push-ups today only while it is still that local day.
    public func repsToday(at date: Date, zone: TimeZone) -> Int? {
        guard let today, today == LocalDate(instant: date, zone: zone).description else { return nil }
        return repsToday
    }
}
