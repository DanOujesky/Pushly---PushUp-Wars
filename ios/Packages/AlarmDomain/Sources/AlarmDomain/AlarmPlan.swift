import CryptoKit
import Foundation

/// One OS alarm the app must have armed (doc 04 §5.2–5.3).
public struct PlannedAlarm: Hashable, Sendable {
    public let osAlarmID: UUID
    public let occurrenceID: String
    public let alarmID: String
    /// "main" or "nag1", "nag2", …
    public let role: String
    public let fireAt: Date
    public let countsForChallenge: Bool

    public var isNag: Bool { role != "main" }

    public init(osAlarmID: UUID, occurrenceID: String, alarmID: String, role: String, fireAt: Date, countsForChallenge: Bool) {
        self.osAlarmID = osAlarmID
        self.occurrenceID = occurrenceID
        self.alarmID = alarmID
        self.role = role
        self.fireAt = fireAt
        self.countsForChallenge = countsForChallenge
    }
}

/// Desired OS alarms — pure; same results as Android `AlarmPlan` and tools/reference/pushly_ref/plan.py.
public enum AlarmPlan {
    /// Never change: alarms already armed on devices are matched by ids derived from it.
    public static let namespace = UUID(uuidString: "6f1c2a52-8b9e-4c1e-9a43-2a1d5e0c7b11") ?? UUID()
    public static let nagInterval: TimeInterval = 120
    public static let androidLookaheadDays = 400

    public static func osAlarmID(occurrenceID: String, role: String) -> UUID {
        uuid5(namespace: namespace, name: "\(occurrenceID)#\(role)")
    }

    /// Rolling window: main alarm per occurrence + nag chain for each day's challenge occurrence.
    public static func windowPlan(_ schedules: [AlarmSchedule], from: Date, zone: TimeZone,
                                  windowDays: Int, nagCount: Int) -> [PlannedAlarm] {
        let occ = AlarmOccurrences.all(schedules, from: from, zone: zone, horizonDays: windowDays)
        let dates = Set(occ.map(\.localDate))
        let challengeIDs = Set(dates.compactMap { AlarmOccurrences.challengeOccurrence(on: $0, in: occ)?.occurrenceID })
        var out: [PlannedAlarm] = []
        for o in occ {
            out.append(entry(o, role: "main", at: o.instant))
            guard challengeIDs.contains(o.occurrenceID), nagCount > 0 else { continue }
            for n in 1...nagCount {
                let at = o.instant.addingTimeInterval(nagInterval * Double(n))
                if at < o.deadline { out.append(entry(o, role: "nag\(n)", at: at)) }
            }
        }
        return out.sorted { $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : $0.osAlarmID.uuidString.lowercased() < $1.osAlarmID.uuidString.lowercased() }
    }

    /// Nags that keep an occurrence ringing from `now` until its deadline (doc 04 §5.2 step 2): `count` alarms,
    /// every 2 min starting at `firstAt`, never at or after the deadline. Roles continue after the planned ones.
    public static func nagChain(for occurrence: Occurrence, firstAt: Date, count: Int, startingRole: Int) -> [PlannedAlarm] {
        (0..<max(count, 0)).compactMap { i in
            let at = firstAt.addingTimeInterval(nagInterval * Double(i))
            guard at < occurrence.deadline else { return nil }
            return entry(occurrence, role: "nag\(startingRole + i)", at: at)
        }
    }

    /// Android arms only the next occurrence of every alarm (doc 04 §6.2). Key = alarm id.
    public static func nextPerAlarm(_ schedules: [AlarmSchedule], from: Date, zone: TimeZone) -> [String: Occurrence?] {
        Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, AlarmOccurrences.next(of: $0, from: from, zone: zone)) })
    }

    static func entry(_ o: Occurrence, role: String, at: Date) -> PlannedAlarm {
        PlannedAlarm(osAlarmID: osAlarmID(occurrenceID: o.occurrenceID, role: role), occurrenceID: o.occurrenceID,
                     alarmID: o.alarmID, role: role, fireAt: at, countsForChallenge: o.countsForChallenge)
    }

    /// RFC 4122 name-based UUID, version 5 (SHA-1).
    public static func uuid5(namespace: UUID, name: String) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
