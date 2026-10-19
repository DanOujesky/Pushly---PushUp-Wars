import Foundation

/// AlarmSchedule rules (doc 04 §2), enforced in the editor and on the server. Error codes are a contract
/// (shared/test-vectors/alarm-validation/cases.json). Mirrors Android `AlarmValidation` and the Python reference.
public enum AlarmValidation {
    public static func isTime(_ value: String?) -> Bool {
        guard let v = value, v.count == 5 else { return false }
        let chars = Array(v)
        guard chars[2] == ":", let h = Int(String(chars[0...1])), let m = Int(String(chars[3...4])),
              (chars[0...1] + chars[3...4]).allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    public static func errors(_ s: AlarmSchedule, today: LocalDate) -> Set<String> {
        var e = Set<String>()
        switch s.kind {
        case .weekly: weekly(s, today: today, into: &e)
        case .oneOff: if parseLocalDateTime(s.oneOff) == nil { e.insert("oneOff.invalid") }
        }
        if let p = s.pause {
            if let from = LocalDate(p.from), let to = LocalDate(p.to) {
                if to < from {
                    e.insert("pause.order")
                } else if from.days(until: to) + 1 > 30 {
                    e.insert("pause.tooLong")
                }
            } else {
                e.insert("pause.invalid")
            }
        }
        mode(s.mode, into: &e)
        return e
    }

    private static func weekly(_ s: AlarmSchedule, today: LocalDate, into e: inout Set<String>) {
        let weekly = s.weekly ?? WeeklyTimes()
        for day in Weekday.allCases {
            if let v = weekly[day], !isTime(v) { e.insert("weekly.\(day.rawValue).time") }
        }
        if weekly.isEmpty && s.overrides.isEmpty { e.insert("weekly.empty") }
        if s.overrides.count > 60 { e.insert("overrides.tooMany") }
        var seen = Set<LocalDate>()
        for ov in s.overrides {
            guard let d = LocalDate(ov.date) else {
                e.insert("overrides.date")
                continue
            }
            if d < today { e.insert("overrides.past") }
            if !seen.insert(d).inserted { e.insert("overrides.duplicate") }
            if ov.skip != true && !isTime(ov.time) { e.insert("overrides.time") }
        }
    }

    private static func mode(_ m: ChallengeMode, into e: inout Set<String>) {
        func inRange(_ v: Int?, _ r: ClosedRange<Int>) -> Bool { v.map(r.contains) ?? false }
        let t = m.modeType
        if t == .ringUntilDone || t == .beatTheClock || t == .escalation, !inRange(m.targetReps, 5...100) {
            e.insert("mode.targetReps")
        }
        if t == .beatTheClock, !inRange(m.windowSeconds, 30...600) { e.insert("mode.windowSeconds") }
        if t == .sprint {
            if ![30, 60, 120].contains(m.windowSeconds ?? -1) { e.insert("mode.windowSeconds") }
            if !inRange(m.minimumReps, 5...100) { e.insert("mode.minimumReps") }
        }
        if t == .sets {
            if !inRange(m.sets, 2...5) { e.insert("mode.sets") }
            if !inRange(m.repsPerSet, 5...50) { e.insert("mode.repsPerSet") }
            if !inRange(m.restSeconds, 15...180) { e.insert("mode.restSeconds") }
        }
        if t == .escalation {
            if !inRange(m.snoozeAddsReps, 1...20) { e.insert("mode.snoozeAddsReps") }
            if !inRange(m.snoozeMinutes, 1...10) { e.insert("mode.snoozeMinutes") }
            if !inRange(m.maxSnoozes, 1...5) { e.insert("mode.maxSnoozes") }
        }
        if t == nil { e.insert("mode.type") }
    }

    /// True when beat-the-clock leaves under 3 s per push-up (editor warning, doc 04 §3).
    public static func isVeryHard(_ m: ChallengeMode) -> Bool {
        guard m.modeType == .beatTheClock, let target = m.targetReps, let window = m.windowSeconds, target > 0 else {
            return false
        }
        return Double(window) / Double(target) < 3
    }

    /// `yyyy-MM-ddTHH:mm` (optionally `:ss`) → date + time.
    public static func parseLocalDateTime(_ value: String?) -> (LocalDate, LocalTime)? {
        guard let v = value else { return nil }
        let parts = v.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2, let d = LocalDate(String(parts[0])) else { return nil }
        var time = String(parts[1])
        if time.count == 8, time.hasSuffix(":00") { time = String(time.prefix(5)) }
        guard let t = LocalTime(time) else { return nil }
        return (d, t)
    }
}
