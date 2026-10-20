import Foundation

/// The complete set of AlarmKit alarms iOS must have armed (doc 04 §5.2–5.3). Pure, so `AlarmScheduler.sync`
/// is a diff against it and both halves can be tested without a device.
public enum IOSAlarmPlan {
    public static let windowDays = 7
    public static let nagCount = 3
    /// Safety cap until the AlarmKit per-app limit is measured (spike P2-01, decisions log D-019).
    public static let maxScheduled = 64
    public static let deadManDelay: TimeInterval = 90

    /// One OS alarm with what it shows.
    public struct Item: Hashable, Sendable {
        public let alarm: PlannedAlarm
        public let title: String
        public let soundID: String
        public let target: Int

        /// Anything that requires re-scheduling when it changes.
        public var signature: String {
            "\(Int(alarm.fireAt.timeIntervalSince1970))|\(alarm.role)|\(title)|\(soundID)|\(target)"
        }
    }

    /// - `active`: occurrences the user is working on (ring states); `finished`: occurrences that ended.
    /// - `practice`: armed practice alarms (kept until they fire).
    public static func desired(schedules: [AlarmSchedule], active: [RingState], finished: [String], practice: [Item],
                               now: Date, zone: TimeZone) -> [Item] {
        let enabled = schedules.filter(\.enabled)
        let byID = Dictionary(enabled.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [Item] = []

        // 1. Rolling window: main alarm per occurrence + nags for each day's challenge occurrence.
        for p in AlarmPlan.windowPlan(enabled, from: now, zone: zone, windowDays: windowDays, nagCount: nagCount) {
            guard let s = byID[p.alarmID] else { continue }
            items.append(Item(alarm: p, title: s.label, soundID: s.sound.id, target: s.mode.totalReps))
        }

        // 2. Occurrences that already rang and are still within their deadline keep nagging until finished, even if
        //    no app code ran since (the AlarmKit stop-intent quirk, doc 04 §5.2).
        let finishedSet = Set(finished)
        var running = Dictionary(active.map { ($0.occurrenceId, $0) }, uniquingKeysWith: { a, _ in a })
        let recentFrom = now.addingTimeInterval(-AlarmOccurrences.deadline)
        let recent = AlarmOccurrences.all(enabled, from: recentFrom, zone: zone, horizonDays: 1)
        for d in Set(recent.map(\.localDate)) {
            guard let c = AlarmOccurrences.challengeOccurrence(on: d, in: recent), c.instant <= now,
                  running[c.occurrenceID] == nil, let s = byID[c.alarmID] else { continue }
            running[c.occurrenceID] = RingState.start(c, schedule: s, rangAt: c.instant)
        }
        for ring in running.values where !finishedSet.contains(ring.occurrenceId) && !ring.isExpired(at: now) && !ring.practice {
            let title = ring.label
            if let until = ring.snoozedUntil.flatMap(ISOInstant.parse), until > now {
                let snooze = AlarmPlan.entry(ring.occurrence, role: "snooze\(ring.snoozesUsed)", at: until)
                items.append(Item(alarm: snooze, title: title, soundID: ring.soundId, target: ring.target))
                continue
            }
            for nag in AlarmPlan.activeChain(for: ring, now: now, count: nagCount) {
                items.append(Item(alarm: nag, title: title, soundID: ring.soundId, target: ring.target))
            }
            if let dm = ring.deadManAt.flatMap(ISOInstant.parse), dm > now, dm < ring.deadline {
                items.append(Item(alarm: AlarmPlan.entry(ring.occurrence, role: "deadman", at: dm),
                                  title: title, soundID: ring.soundId, target: ring.target))
            }
        }

        // 3. Practice alarms ("Test my alarm").
        items += practice.filter { $0.alarm.fireAt > now }

        var seen = Set<UUID>()
        let unique = items.filter { seen.insert($0.alarm.osAlarmID).inserted }
        return Array(unique.sorted { $0.alarm.fireAt < $1.alarm.fireAt }.prefix(maxScheduled))
    }
}
