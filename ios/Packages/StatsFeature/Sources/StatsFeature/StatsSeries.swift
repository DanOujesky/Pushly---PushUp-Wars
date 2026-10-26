import Foundation

/// Pure chart data shaping for the dashboard (doc 10 §2). Mirrors Android `StatsSeries` — same buckets, same steps.
public enum StatsSeries {
    public enum Bucket: String, Sendable { case day, week, month }

    public struct Bar: Hashable, Sendable, Identifiable {
        /// First local day of the bucket (YYYY-MM-DD).
        public var start: String
        public var wake: Int
        public var battle: Int
        public var training: Int
        public var id: String { start }
        public var total: Int { wake + battle + training }
    }

    public struct Point: Hashable, Sendable, Identifiable {
        public var date: String
        public var value: Int
        public var isRecord = false
        public var id: String { date }
    }

    static let calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)   // weeks start on Monday
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }()

    /// Local dates are handled as UTC midnights (no DST jumps); Sendable, unlike DateFormatter.
    static let dayStyle = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC") ?? .gmt)
        .year().month().day().dateSeparator(.dash)

    public static func date(_ s: String) -> Date? { try? Date(s, strategy: dayStyle) }
    public static func string(_ d: Date) -> String { d.formatted(dayStyle) }

    /// Day bars up to 31 days, week bars up to 53 weeks, month bars beyond.
    public static func bucket(from: String, to: String) -> Bucket {
        guard let a = date(from), let b = date(to) else { return .day }
        let days = (calendar.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        return days <= 31 ? .day : days <= 371 ? .week : .month
    }

    static func bucketStart(_ d: Date, _ bucket: Bucket) -> Date {
        switch bucket {
        case .day: d
        case .week: calendar.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        case .month: calendar.dateInterval(of: .month, for: d)?.start ?? d
        }
    }

    static func step(_ d: Date, _ bucket: Bucket) -> Date {
        let component: Calendar.Component = bucket == .day ? .day : bucket == .week ? .weekOfYear : .month
        return calendar.date(byAdding: component, value: 1, to: d) ?? d.addingTimeInterval(86_400)
    }

    /// Stacked bars for the whole period, empty buckets included.
    public static func bars(_ stats: StatsData) -> [Bar] {
        let bucket = bucket(from: stats.from, to: stats.to)
        guard let from = date(stats.from), let to = date(stats.to) else { return [] }
        var sums: [String: Bar] = [:]
        for day in stats.daily {
            guard let d = date(day.date) else { continue }
            let key = string(bucketStart(d, bucket))
            var bar = sums[key] ?? Bar(start: key, wake: 0, battle: 0, training: 0)
            bar.wake += day.wake
            bar.battle += day.battle
            bar.training += day.training
            sums[key] = bar
        }
        var out: [Bar] = []
        var cursor = bucketStart(from, bucket)
        while cursor <= to {
            let key = string(cursor)
            out.append(sums[key] ?? Bar(start: key, wake: 0, battle: 0, training: 0))
            cursor = step(cursor, bucket)
        }
        return out
    }

    /// Running total of all reps (starts at everything before the period).
    public static func cumulative(_ stats: StatsData) -> [Point] {
        var total = stats.cumulativeBefore
        var out = [Point(date: stats.from, value: total)]
        for day in stats.daily {
            total += day.total
            if day.date == stats.from { out[0].value = total } else { out.append(Point(date: day.date, value: total)) }
        }
        if out.last?.date != stats.to { out.append(Point(date: stats.to, value: total)) }
        return out
    }

    /// Milestones crossed in the period (doc 10 §3).
    public static let milestones = [100, 500, 1000, 2500, 5000, 10_000, 25_000, 50_000, 100_000]

    public static func milestonesReached(_ stats: StatsData) -> [Point] {
        var total = stats.cumulativeBefore
        var out: [Point] = []
        for day in stats.daily {
            let before = total
            total += day.total
            for m in milestones where before < m && total >= m {
                out.append(Point(date: day.date, value: m))
            }
        }
        return out
    }

    /// Best set per active day; `isRecord` where it beat every earlier day of the period.
    public static func bestSets(_ stats: StatsData) -> [Point] {
        var best = 0
        return stats.daily.filter { $0.bestSet > 0 }.map { day in
            defer { best = max(best, day.bestSet) }
            return Point(date: day.date, value: day.bestSet, isRecord: day.bestSet > best)
        }
    }

    /// Heatmap intensity 0…4 (doc 14 §1: 5-step sequential lime).
    public static func heatLevel(_ reps: Int) -> Int {
        switch reps {
        case ..<1: 0
        case ..<20: 1
        case ..<50: 2
        case ..<100: 3
        default: 4
        }
    }

    public struct HeatCell: Hashable, Sendable, Identifiable {
        public var date: String
        public var reps: Int
        /// Column (week, 0 = oldest) and row (0 = Monday).
        public var week: Int
        public var weekday: Int
        public var level: Int { StatsSeries.heatLevel(reps) }
        public var id: String { date }
    }

    /// The last 53 weeks ending with the week of `today`, Monday rows.
    public static func heatmap(_ stats: StatsData, today: String) -> [HeatCell] {
        guard let end = date(today) else { return [] }
        let lastWeek = bucketStart(end, .week)
        guard let first = calendar.date(byAdding: .weekOfYear, value: -52, to: lastWeek) else { return [] }
        let reps = Dictionary(stats.heatmap.map { ($0.date, $0.reps) }, uniquingKeysWith: +)
        var out: [HeatCell] = []
        var d = first
        var index = 0
        while d <= end {
            let key = string(d)
            out.append(HeatCell(date: key, reps: reps[key] ?? 0, week: index / 7, weekday: index % 7))
            index += 1
            d = step(d, .day)
        }
        return out
    }

    /// Change vs. the previous period: nil when there's nothing to compare.
    public static func delta(_ now: Int?, _ before: Int?) -> Int? {
        guard let now, let before, before > 0 || now > 0 else { return nil }
        return now - before
    }
}

extension StatsSeries {
    /// Daily totals for the last `count` local days up to `stats.to` (missing days = 0), oldest first — the Profile mini
    /// chart (D-077).
    public static func lastDays(_ stats: StatsData, count: Int = 7) -> [(day: String, total: Int)] {
        guard let to = date(stats.to) else { return [] }
        var totals: [String: Int] = [:]
        for d in stats.daily { totals[d.date, default: 0] += d.total }
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: to).map { d in
                let key = string(d)
                return (day: key, total: totals[key] ?? 0)
            }
        }
    }
}
