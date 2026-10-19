import Foundation

/// A calendar date without time zone (`yyyy-MM-dd`), proleptic Gregorian.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`; nil for anything else or an impossible date.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let candidate = LocalDate(year: y, month: m, day: d)
        guard candidate.adding(days: 0) == candidate else { return nil }
        self = candidate
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalDate(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(raw)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Midnight of this date as if it were UTC — a time-zone-free handle for date arithmetic.
    var utcMidnight: Date {
        LocalDate.utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int) -> LocalDate {
        let date = utcMidnight.addingTimeInterval(TimeInterval(days) * 86_400)
        return LocalDate(utc: date)
    }

    /// Days from `self` to `other` (positive when `other` is later).
    public func days(until other: LocalDate) -> Int {
        Int((other.utcMidnight.timeIntervalSince(utcMidnight) / 86_400).rounded())
    }

    public var weekday: Weekday {
        // Calendar weekday: 1 = Sunday … 7 = Saturday
        switch LocalDate.utcCalendar.component(.weekday, from: utcMidnight) {
        case 1: .sun
        case 2: .mon
        case 3: .tue
        case 4: .wed
        case 5: .thu
        case 6: .fri
        default: .sat
        }
    }

    /// The local date of `instant` in `zone`.
    public init(instant: Date, zone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: instant)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    init(utc date: Date) {
        let c = LocalDate.utcCalendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal
    }()
}

/// Wall-clock time `HH:mm`, minute precision.
public struct LocalTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Parses strict `HH:mm` (24 h). "6:30" and "24:00" are rejected.
    public init?(_ string: String?) {
        guard let s = string, AlarmValidation.isTime(s),
              let h = Int(s.prefix(2)), let m = Int(s.suffix(2)) else { return nil }
        self.init(hour: h, minute: m)
    }

    public var description: String { String(format: "%02d:%02d", hour, minute) }
    public var minutesOfDay: Int { hour * 60 + minute }

    public static func < (a: LocalTime, b: LocalTime) -> Bool { a.minutesOfDay < b.minutesOfDay }
}

public enum Weekday: String, CaseIterable, Sendable, Codable {
    case mon, tue, wed, thu, fri, sat, sun
}
