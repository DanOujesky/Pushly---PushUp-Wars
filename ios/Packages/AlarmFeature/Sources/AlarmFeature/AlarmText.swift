import AlarmDomain
import Foundation

/// Clock time in the user's 12/24 h preference, split so the digits can be huge and "AM/PM" small.
public enum TimeText {
    public struct Parts: Sendable, Equatable {
        public let main: String
        public let suffix: String?
    }

    static var uses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "HH"
        return !format.contains("a")
    }

    public static func parts(_ t: LocalTime, twentyFour: Bool = uses24Hour) -> Parts {
        if twentyFour { return Parts(main: String(format: "%02d:%02d", t.hour, t.minute), suffix: nil) }
        let h = t.hour % 12 == 0 ? 12 : t.hour % 12
        return Parts(main: String(format: "%d:%02d", h, t.minute), suffix: t.hour < 12 ? "AM" : "PM")
    }

    public static func short(_ t: LocalTime) -> String {
        let p = parts(t)
        return [p.main, p.suffix].compactMap { $0 }.joined(separator: " ")
    }

    public static func short(_ hhmm: String?) -> String? { LocalTime(hhmm).map(short) }

    public static func localTime(_ date: Date, zone: TimeZone = .current) -> LocalTime {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return LocalTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    /// "in 7 h 12 min"
    public static func until(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 0)
        let h = minutes / 60, m = minutes % 60
        if h >= 24 { return String(localized: "in \(h / 24) d \(h % 24) h") }
        if h > 0 { return String(localized: "in \(h) h \(m) min") }
        return String(localized: "in \(max(m, 1)) min")
    }

    public static func dayShort(_ day: Weekday) -> String {
        Calendar.current.shortWeekdaySymbols[day.calendarIndex]
    }

    public static func dayNarrow(_ day: Weekday) -> String {
        Calendar.current.veryShortWeekdaySymbols[day.calendarIndex]
    }
}

extension Weekday {
    /// Index into `Calendar.*WeekdaySymbols` (Sunday = 0).
    var calendarIndex: Int {
        switch self {
        case .sun: 0
        case .mon: 1
        case .tue: 2
        case .wed: 3
        case .thu: 4
        case .fri: 5
        case .sat: 6
        }
    }

    /// Monday-first order used in the editor.
    static var mondayFirst: [Weekday] { [.mon, .tue, .wed, .thu, .fri, .sat, .sun] }
}

public enum ModeText {
    public static func name(_ type: ModeType) -> String {
        switch type {
        case .ringUntilDone: String(localized: "Ring until done")
        case .beatTheClock: String(localized: "Beat the clock")
        case .sprint: String(localized: "Sprint")
        case .sets: String(localized: "Sets")
        case .escalation: String(localized: "Escalation")
        }
    }

    public static func description(_ type: ModeType) -> String {
        switch type {
        case .ringUntilDone: String(localized: "The alarm rings until you finish your push-ups.")
        case .beatTheClock:
            String(localized: "Finish all push-ups before the timer runs out — the clock starts when the alarm rings.")
        case .sprint: String(localized: "As many push-ups as you can in the window. Reach the minimum to win.")
        case .sets: String(localized: "Several sets with short rests. The alarm rings again when the rest is over.")
        case .escalation: String(localized: "You may snooze, but every snooze adds push-ups.")
        }
    }

    /// "Ring until done · 20 push-ups"
    public static func summary(_ m: ChallengeMode) -> String {
        guard let type = m.modeType else { return "" }
        let detail: String = switch type {
        case .ringUntilDone, .escalation: String(localized: "\(m.targetReps ?? 0) push-ups")
        case .beatTheClock: String(localized: "\(m.targetReps ?? 0) push-ups in \(m.windowSeconds ?? 0) s")
        case .sprint: String(localized: "min. \(m.minimumReps ?? 0) in \(m.windowSeconds ?? 0) s")
        case .sets: String(localized: "\(m.sets ?? 0) × \(m.repsPerSet ?? 0) push-ups")
        }
        return "\(name(type)) · \(detail)"
    }
}

public enum ScheduleText {
    /// "Mon–Fri", "Every day", "Weekends", "Mon, Wed, Fri" or the one-off date.
    public static func days(_ s: AlarmSchedule) -> String {
        if s.kind == .oneOff { return s.oneOff.map { String($0.prefix(10)) } ?? "" }
        guard let weekly = s.weekly else { return "" }
        let on = Weekday.mondayFirst.filter { weekly[$0] != nil }
        if on.count == 7 { return String(localized: "Every day") }
        if on == [.mon, .tue, .wed, .thu, .fri] { return String(localized: "Mon–Fri") }
        if on == [.sat, .sun] { return String(localized: "Weekends") }
        if on.isEmpty { return String(localized: "No days") }
        return on.map(TimeText.dayShort).joined(separator: ", ")
    }

    /// The alarm's time if all its days share one time, else nil ("different times").
    public static func singleTime(_ s: AlarmSchedule) -> String? {
        if s.kind == .oneOff { return s.oneOff.map { String($0.suffix(5)) } }
        let times = Weekday.mondayFirst.compactMap { s.weekly?[$0] }
        let unique = Set(times)
        return unique.count == 1 ? unique.first : nil
    }
}
