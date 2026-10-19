import Foundation

/// One concrete ring of an alarm on a local date (doc 04 §1). ID: `"{alarmId}:{yyyy-MM-dd}"`.
public struct Occurrence: Hashable, Sendable, Identifiable {
    public let occurrenceID: String
    public let alarmID: String
    public let localDate: LocalDate
    public let instant: Date
    public let countsForChallenge: Bool

    public var id: String { occurrenceID }

    public init(occurrenceID: String, alarmID: String, localDate: LocalDate, instant: Date, countsForChallenge: Bool) {
        self.occurrenceID = occurrenceID
        self.alarmID = alarmID
        self.localDate = localDate
        self.instant = instant
        self.countsForChallenge = countsForChallenge
    }

    /// Completion deadline of every mode: T0 + 30 min (doc 04 §3).
    public var deadline: Date { instant.addingTimeInterval(AlarmOccurrences.deadline) }
}

/// Pure occurrence computation (doc 04 §4) — same results as Android `AlarmOccurrences` and
/// tools/reference/pushly_ref/occurrences.py for every vector in shared/test-vectors/alarm-occurrences.
public enum AlarmOccurrences {
    public static let deadline: TimeInterval = 30 * 60
    private static let maxGapMinutes = 180

    /// Wall-clock time the alarm rings on local date `d`, or nil. No time zones involved.
    public static func localTime(for s: AlarmSchedule, on d: LocalDate) -> LocalTime? {
        guard s.enabled else { return nil }
        if let p = s.pause, let from = LocalDate(p.from), let to = LocalDate(p.to), from <= d, d <= to { return nil }
        switch s.kind {
        case .oneOff:
            guard let parsed = AlarmValidation.parseLocalDateTime(s.oneOff), parsed.0 == d else { return nil }
            return parsed.1
        case .weekly:
            if let ov = s.overrides.first(where: { $0.date == d.description }) {
                return ov.skip == true ? nil : LocalTime(ov.time)
            }
            return LocalTime(s.weekly?[d.weekday])
        }
    }

    /// Local date + time → instant: DST gap → first valid minute after it; overlap → first (earlier) instance.
    public static func resolveLocal(_ d: LocalDate, _ t: LocalTime, zone: TimeZone) -> Date {
        let naiveBase = d.utcMidnight.addingTimeInterval(TimeInterval(t.minutesOfDay * 60))
        for minutes in 0...maxGapMinutes {
            let naive = naiveBase.addingTimeInterval(TimeInterval(minutes * 60))
            let offsets = Set([-86_400.0, 0, 86_400].map { zone.secondsFromGMT(for: naive.addingTimeInterval($0)) })
            let valid = offsets
                .map { naive.addingTimeInterval(-TimeInterval($0)) }
                .filter { candidate in
                    let offset = zone.secondsFromGMT(for: candidate)
                    return candidate.addingTimeInterval(TimeInterval(offset)) == naive
                }
            if let earliest = valid.min() { return earliest }
        }
        return naiveBase.addingTimeInterval(-TimeInterval(zone.secondsFromGMT(for: naiveBase)))
    }

    /// Occurrences of one alarm for local dates [today, today + horizonDays], strictly after `from`, sorted.
    public static func occurrences(of s: AlarmSchedule, from: Date, zone: TimeZone, horizonDays: Int) -> [Occurrence] {
        let today = LocalDate(instant: from, zone: zone)
        var out: [Occurrence] = []
        for offset in 0...max(horizonDays, 0) {
            let d = today.adding(days: offset)
            guard let t = localTime(for: s, on: d) else { continue }
            let instant = resolveLocal(d, t, zone: zone)
            guard instant > from else { continue }
            out.append(Occurrence(occurrenceID: "\(s.id):\(d)", alarmID: s.id, localDate: d, instant: instant,
                                  countsForChallenge: s.countsForChallenge))
        }
        return out.sorted(by: order)
    }

    public static func all(_ schedules: [AlarmSchedule], from: Date, zone: TimeZone, horizonDays: Int) -> [Occurrence] {
        schedules.flatMap { occurrences(of: $0, from: from, zone: zone, horizonDays: horizonDays) }.sorted(by: order)
    }

    /// The one occurrence that counts for the Wake Challenge on `date`: earliest challenge alarm, ties by alarm id.
    public static func challengeOccurrence(on date: LocalDate, in occurrences: [Occurrence]) -> Occurrence? {
        occurrences.filter { $0.localDate == date && $0.countsForChallenge }.min(by: order)
    }

    /// Next ring of `s` (looks ahead far enough for one-off alarms, overrides and pauses).
    public static func next(of s: AlarmSchedule, from: Date, zone: TimeZone) -> Occurrence? {
        occurrences(of: s, from: from, zone: zone, horizonDays: AlarmPlan.androidLookaheadDays).first
    }

    static func order(_ a: Occurrence, _ b: Occurrence) -> Bool {
        a.instant != b.instant ? a.instant < b.instant : a.alarmID < b.alarmID
    }
}
