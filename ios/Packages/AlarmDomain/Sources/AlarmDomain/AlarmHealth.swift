import Foundation

/// Everything the health check needs, read from the OS by the platform layer. nil = not applicable on this platform.
public struct HealthInput: Sendable {
    public var hasEnabledAlarms: Bool
    public var alarmKitAuthorized: Bool?
    public var exactAlarmAllowed: Bool?
    public var fullScreenIntentAllowed: Bool?
    public var notificationsAllowed: Bool?
    public var alarmChannelOk: Bool?
    public var batteryRestrictedOnAggressiveOem: Bool?
    public var cameraDenied: Bool
    public var nextAlarmArmed: Bool?
    public var alarmVolumeZero: Bool?
    public var customSoundMissing: Bool

    public init(hasEnabledAlarms: Bool, alarmKitAuthorized: Bool? = nil, exactAlarmAllowed: Bool? = nil,
                fullScreenIntentAllowed: Bool? = nil, notificationsAllowed: Bool? = nil, alarmChannelOk: Bool? = nil,
                batteryRestrictedOnAggressiveOem: Bool? = nil, cameraDenied: Bool = false, nextAlarmArmed: Bool? = nil,
                alarmVolumeZero: Bool? = nil, customSoundMissing: Bool = false) {
        self.hasEnabledAlarms = hasEnabledAlarms
        self.alarmKitAuthorized = alarmKitAuthorized
        self.exactAlarmAllowed = exactAlarmAllowed
        self.fullScreenIntentAllowed = fullScreenIntentAllowed
        self.notificationsAllowed = notificationsAllowed
        self.alarmChannelOk = alarmChannelOk
        self.batteryRestrictedOnAggressiveOem = batteryRestrictedOnAggressiveOem
        self.cameraDenied = cameraDenied
        self.nextAlarmArmed = nextAlarmArmed
        self.alarmVolumeZero = alarmVolumeZero
        self.customSoundMissing = customSoundMissing
    }
}

public enum HealthSeverity: Int, Sendable, Comparable {
    case critical, warning

    public static func < (a: HealthSeverity, b: HealthSeverity) -> Bool { a.rawValue < b.rawValue }
}

/// Alarm health issues (doc 04 §8). Codes are identical on Android.
public enum HealthIssue: String, CaseIterable, Sendable {
    case alarmKitNotAuthorized, exactAlarmMissing, fullScreenIntentMissing, notificationsBlocked, alarmChannelMuted
    case cameraDenied, nextAlarmNotArmed, batteryRestricted, alarmVolumeZero, customSoundMissing

    public var severity: HealthSeverity {
        switch self {
        case .batteryRestricted, .alarmVolumeZero, .customSoundMissing: .warning
        default: .critical
        }
    }
}

public enum AlarmHealth {
    /// Issues in display order (critical first, then table order). No alarms → nothing to warn about.
    public static func issues(_ i: HealthInput) -> [HealthIssue] {
        guard i.hasEnabledAlarms else { return [] }
        var out: [HealthIssue] = []
        if i.alarmKitAuthorized == false { out.append(.alarmKitNotAuthorized) }
        if i.exactAlarmAllowed == false { out.append(.exactAlarmMissing) }
        if i.fullScreenIntentAllowed == false { out.append(.fullScreenIntentMissing) }
        if i.notificationsAllowed == false { out.append(.notificationsBlocked) }
        if i.alarmChannelOk == false { out.append(.alarmChannelMuted) }
        if i.cameraDenied { out.append(.cameraDenied) }
        // Only meaningful when the OS lets us schedule at all; otherwise the permission issue explains it.
        if i.nextAlarmArmed == false, out.isEmpty { out.append(.nextAlarmNotArmed) }
        if i.batteryRestrictedOnAggressiveOem == true { out.append(.batteryRestricted) }
        if i.alarmVolumeZero == true { out.append(.alarmVolumeZero) }
        if i.customSoundMissing { out.append(.customSoundMissing) }
        return out.enumerated().sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }.map(\.element)
    }
}

/// Idempotent scheduler diff (doc 04 §5.4): what to cancel and what to (re)schedule so the OS matches the plan.
public enum AlarmSyncDiff {
    public struct Desired<Payload: Sendable>: Sendable {
        public let key: String
        public let signature: String
        public let payload: Payload

        public init(key: String, signature: String, payload: Payload) {
            self.key = key
            self.signature = signature
            self.payload = payload
        }
    }

    public struct Result<Payload: Sendable>: Sendable {
        public let cancel: [String]
        public let schedule: [Desired<Payload>]
        public var isEmpty: Bool { cancel.isEmpty && schedule.isEmpty }
    }

    /// `current` = key → signature of what the OS has armed now (according to the OS and our record of it).
    public static func compute<P>(desired: [Desired<P>], current: [String: String]) -> Result<P> {
        let wanted = Dictionary(desired.map { ($0.key, $0.signature) }, uniquingKeysWith: { a, _ in a })
        let cancel = current.filter { wanted[$0.key] != $0.value }.keys.sorted()
        let schedule = desired.filter { current[$0.key] != $0.signature }
        return Result(cancel: cancel, schedule: schedule)
    }
}

public extension AlarmPlan {
    /// Nags that keep an in-progress occurrence ringing (doc 04 §5.2 step 2): the next `count` slots of the
    /// 2-minute grid after `now`, before the deadline. Roles match `windowPlan` numbering (nagN = T0 + 2N min).
    static func activeChain(for ring: RingState, now: Date, count: Int = 3) -> [PlannedAlarm] {
        guard !ring.isExpired(at: now) else { return [] }
        let o = ring.occurrence
        var out: [PlannedAlarm] = []
        var n = 1
        while out.count < count {
            let at = o.instant.addingTimeInterval(nagInterval * Double(n))
            if at >= o.deadline { break }
            if at > now { out.append(entry(o, role: "nag\(n)", at: at)) }
            n += 1
        }
        return out
    }
}

public extension AlarmHealth {
    /// Local hour of the evening health reminder (doc 04 §8).
    static let reminderHour = 21

    /// When to show the evening reminder: the next 21:00 local, but only if a critical issue exists and an alarm is
    /// due within 24 h of that moment. nil = no reminder. Same rule as Android `AlarmHealth.eveningReminder`.
    static func eveningReminder(critical: Bool, nextAlarm: Date?, now: Date, zone: TimeZone) -> Date? {
        guard critical, let nextAlarm else { return nil }
        let today = LocalDate(instant: now, zone: zone)
        let time = LocalTime(hour: reminderHour, minute: 0)
        var at = AlarmOccurrences.resolveLocal(today, time, zone: zone)
        if at <= now { at = AlarmOccurrences.resolveLocal(today.adding(days: 1), time, zone: zone) }
        guard nextAlarm > at, nextAlarm.timeIntervalSince(at) <= 24 * 3600 else { return nil }
        return at
    }
}
