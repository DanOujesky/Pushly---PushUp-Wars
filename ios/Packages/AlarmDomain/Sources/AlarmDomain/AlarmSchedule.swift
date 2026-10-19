import Foundation

/// A user-defined alarm (doc 04 §2). Wire shape = shared/contracts/alarm-schedule.schema.json; same fields as Android.
public struct AlarmSchedule: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var version: Int
    public var label: String
    public var enabled: Bool
    public var countsForChallenge: Bool
    public var kind: AlarmKind
    public var weekly: WeeklyTimes?
    /// Local date-time `yyyy-MM-ddTHH:mm`, when `kind == .oneOff`.
    public var oneOff: String?
    public var overrides: [AlarmOverride]
    public var pause: AlarmPause?
    public var mode: ChallengeMode
    public var sound: AlarmSound
    public var vibration: String?
    public var preAlarmMinutes: Int?
    public var bedtimeReminderMinutes: Int?
    public var updatedAt: String?

    public static let maxAlarmsPerUser = 20
    public static let maxLabelLength = 40

    public init(
        id: String,
        version: Int = 1,
        label: String = "",
        enabled: Bool = true,
        countsForChallenge: Bool = true,
        kind: AlarmKind = .weekly,
        weekly: WeeklyTimes? = nil,
        oneOff: String? = nil,
        overrides: [AlarmOverride] = [],
        pause: AlarmPause? = nil,
        mode: ChallengeMode = .default,
        sound: AlarmSound = AlarmSound(),
        vibration: String? = nil,
        preAlarmMinutes: Int? = nil,
        bedtimeReminderMinutes: Int? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.version = version
        self.label = label
        self.enabled = enabled
        self.countsForChallenge = countsForChallenge
        self.kind = kind
        self.weekly = weekly
        self.oneOff = oneOff
        self.overrides = overrides
        self.pause = pause
        self.mode = mode
        self.sound = sound
        self.vibration = vibration
        self.preAlarmMinutes = preAlarmMinutes
        self.bedtimeReminderMinutes = bedtimeReminderMinutes
        self.updatedAt = updatedAt
    }

    /// New alarm as the editor opens it: weekdays 06:30, ring until 20 push-ups.
    public static func newDefault(id: String) -> AlarmSchedule {
        AlarmSchedule(id: id, weekly: WeeklyTimes(mon: "06:30", tue: "06:30", wed: "06:30", thu: "06:30", fri: "06:30"))
    }

    enum CodingKeys: String, CodingKey {
        case id, version, label, enabled, countsForChallenge, kind, weekly, oneOff, overrides, pause, mode, sound
        case vibration, preAlarmMinutes, bedtimeReminderMinutes, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        countsForChallenge = try c.decodeIfPresent(Bool.self, forKey: .countsForChallenge) ?? true
        kind = try c.decodeIfPresent(AlarmKind.self, forKey: .kind) ?? .weekly
        weekly = try c.decodeIfPresent(WeeklyTimes.self, forKey: .weekly)
        oneOff = try c.decodeIfPresent(String.self, forKey: .oneOff)
        overrides = try c.decodeIfPresent([AlarmOverride].self, forKey: .overrides) ?? []
        pause = try c.decodeIfPresent(AlarmPause.self, forKey: .pause)
        mode = try c.decodeIfPresent(ChallengeMode.self, forKey: .mode) ?? .default
        sound = try c.decodeIfPresent(AlarmSound.self, forKey: .sound) ?? AlarmSound()
        vibration = try c.decodeIfPresent(String.self, forKey: .vibration)
        preAlarmMinutes = try c.decodeIfPresent(Int.self, forKey: .preAlarmMinutes)
        bedtimeReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .bedtimeReminderMinutes)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

public enum AlarmKind: String, Codable, Sendable {
    case weekly, oneOff
}

/// Wall-clock time per weekday (`HH:mm`); nil = no alarm that day.
public struct WeeklyTimes: Codable, Hashable, Sendable {
    public var mon: String?
    public var tue: String?
    public var wed: String?
    public var thu: String?
    public var fri: String?
    public var sat: String?
    public var sun: String?

    public init(mon: String? = nil, tue: String? = nil, wed: String? = nil, thu: String? = nil,
                fri: String? = nil, sat: String? = nil, sun: String? = nil) {
        self.mon = mon
        self.tue = tue
        self.wed = wed
        self.thu = thu
        self.fri = fri
        self.sat = sat
        self.sun = sun
    }

    public subscript(day: Weekday) -> String? {
        get {
            switch day {
            case .mon: mon
            case .tue: tue
            case .wed: wed
            case .thu: thu
            case .fri: fri
            case .sat: sat
            case .sun: sun
            }
        }
        set {
            switch day {
            case .mon: mon = newValue
            case .tue: tue = newValue
            case .wed: wed = newValue
            case .thu: thu = newValue
            case .fri: fri = newValue
            case .sat: sat = newValue
            case .sun: sun = newValue
            }
        }
    }

    public var isEmpty: Bool { Weekday.allCases.allSatisfy { self[$0] == nil } }
}

/// A date-specific change: another time, or `skip` = no alarm that day.
public struct AlarmOverride: Codable, Hashable, Sendable {
    public var date: String
    public var time: String?
    public var skip: Bool?

    public init(date: String, time: String? = nil, skip: Bool? = nil) {
        self.date = date
        self.time = time
        self.skip = skip
    }
}

public struct AlarmPause: Codable, Hashable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The challenge modes (doc 04 §3). `type` stays a string so values from newer clients survive a round trip.
public struct ChallengeMode: Codable, Hashable, Sendable {
    public var type: String
    public var targetReps: Int?
    public var windowSeconds: Int?
    public var minimumReps: Int?
    public var sets: Int?
    public var repsPerSet: Int?
    public var restSeconds: Int?
    public var snoozeAddsReps: Int?
    public var snoozeMinutes: Int?
    public var maxSnoozes: Int?

    public init(type: String, targetReps: Int? = nil, windowSeconds: Int? = nil, minimumReps: Int? = nil,
                sets: Int? = nil, repsPerSet: Int? = nil, restSeconds: Int? = nil,
                snoozeAddsReps: Int? = nil, snoozeMinutes: Int? = nil, maxSnoozes: Int? = nil) {
        self.type = type
        self.targetReps = targetReps
        self.windowSeconds = windowSeconds
        self.minimumReps = minimumReps
        self.sets = sets
        self.repsPerSet = repsPerSet
        self.restSeconds = restSeconds
        self.snoozeAddsReps = snoozeAddsReps
        self.snoozeMinutes = snoozeMinutes
        self.maxSnoozes = maxSnoozes
    }

    public var modeType: ModeType? { ModeType(rawValue: type) }

    /// Push-ups needed without snoozes (sets: all sets together).
    public var totalReps: Int {
        switch modeType {
        case .sets: (sets ?? 0) * (repsPerSet ?? 0)
        case .sprint: minimumReps ?? 0
        default: targetReps ?? 0
        }
    }

    public static let `default` = ChallengeMode(type: ModeType.ringUntilDone.rawValue, targetReps: 20)

    /// Sensible starting values when the user switches mode in the editor (all valid per doc 04 §2).
    public static func defaults(for type: ModeType, targetReps: Int = 20) -> ChallengeMode {
        switch type {
        case .ringUntilDone: ChallengeMode(type: type.rawValue, targetReps: targetReps)
        case .beatTheClock: ChallengeMode(type: type.rawValue, targetReps: min(max(targetReps, 5), 100), windowSeconds: 120)
        case .sprint: ChallengeMode(type: type.rawValue, windowSeconds: 60, minimumReps: 15)
        case .sets: ChallengeMode(type: type.rawValue, sets: 3, repsPerSet: 10, restSeconds: 45)
        case .escalation:
            ChallengeMode(type: type.rawValue, targetReps: targetReps, snoozeAddsReps: 5, snoozeMinutes: 5, maxSnoozes: 3)
        }
    }
}

public enum ModeType: String, CaseIterable, Sendable {
    case ringUntilDone, beatTheClock, sprint, sets, escalation
}

public struct AlarmSound: Codable, Hashable, Sendable {
    public var id: String
    public var rampSeconds: Int?

    public init(id: String = AlarmSounds.defaultID, rampSeconds: Int? = nil) {
        self.id = id
        self.rampSeconds = rampSeconds
    }
}

/// Sounds shipped in the app (original synthesized tones until a licensed pack arrives — decisions log Q-02).
public enum AlarmSounds {
    public static let defaultID = "bundled.pulse"
    public static let bundled = ["bundled.pulse", "bundled.rise", "bundled.arena", "bundled.classic"]

    /// File name (without extension) for a sound id; unknown ids fall back to the default (doc 04 §8).
    public static func resourceName(_ id: String) -> String {
        String((bundled.contains(id) ? id : defaultID).dropFirst("bundled.".count))
    }
}
