import Foundation

/// An occurrence that is ringing or waiting for its push-ups (doc 04 §3, §7). Persisted in `AlarmDocument.active`
/// so a killed app can resume the challenge. Same rules and JSON shape as Android `RingState`.
public struct RingState: Codable, Hashable, Sendable {
    public var occurrenceId: String
    public var alarmId: String
    public var label: String
    /// Scheduled ring time T0 (ISO instant).
    public var t0: String
    /// When the phone actually rang (ISO instant); differs from T0 if the OS delivered late.
    public var rangAt: String
    public var mode: ChallengeMode
    public var countsForChallenge: Bool
    public var practice: Bool
    public var snoozesUsed: Int
    /// While snoozed (escalation only): ISO instant the alarm rings again.
    public var snoozedUntil: String?
    public var soundId: String
    /// iOS dead-man's switch (doc 04 §5.2 step 3): a nag armed while the wake session is open.
    public var deadManAt: String?

    public init(occurrenceId: String, alarmId: String, label: String, t0: String, rangAt: String, mode: ChallengeMode,
                countsForChallenge: Bool, practice: Bool = false, snoozesUsed: Int = 0, snoozedUntil: String? = nil,
                soundId: String = AlarmSounds.defaultID, deadManAt: String? = nil) {
        self.occurrenceId = occurrenceId
        self.alarmId = alarmId
        self.label = label
        self.t0 = t0
        self.rangAt = rangAt
        self.mode = mode
        self.countsForChallenge = countsForChallenge
        self.practice = practice
        self.snoozesUsed = snoozesUsed
        self.snoozedUntil = snoozedUntil
        self.soundId = soundId
        self.deadManAt = deadManAt
    }

    enum CodingKeys: String, CodingKey {
        case occurrenceId, alarmId, label, t0, rangAt, mode, countsForChallenge, practice, snoozesUsed, snoozedUntil, soundId, deadManAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        occurrenceId = try c.decode(String.self, forKey: .occurrenceId)
        alarmId = try c.decode(String.self, forKey: .alarmId)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        t0 = try c.decode(String.self, forKey: .t0)
        rangAt = try c.decodeIfPresent(String.self, forKey: .rangAt) ?? t0
        mode = try c.decode(ChallengeMode.self, forKey: .mode)
        countsForChallenge = try c.decodeIfPresent(Bool.self, forKey: .countsForChallenge) ?? false
        practice = try c.decodeIfPresent(Bool.self, forKey: .practice) ?? false
        snoozesUsed = try c.decodeIfPresent(Int.self, forKey: .snoozesUsed) ?? 0
        snoozedUntil = try c.decodeIfPresent(String.self, forKey: .snoozedUntil)
        soundId = try c.decodeIfPresent(String.self, forKey: .soundId) ?? AlarmSounds.defaultID
        deadManAt = try c.decodeIfPresent(String.self, forKey: .deadManAt)
    }

    public var t0Date: Date { ISOInstant.parse(t0) ?? .distantPast }
    public var rangAtDate: Date { ISOInstant.parse(rangAt) ?? t0Date }

    /// Completion deadline: T0 + 30 min for every mode.
    public var deadline: Date { t0Date.addingTimeInterval(AlarmOccurrences.deadline) }

    /// Push-ups needed now: escalation adds `snoozeAddsReps` per snooze.
    public var target: Int {
        mode.modeType == .escalation ? (mode.targetReps ?? 0) + snoozesUsed * (mode.snoozeAddsReps ?? 0) : mode.totalReps
    }

    public var canSnooze: Bool { mode.modeType == .escalation && snoozesUsed < (mode.maxSnoozes ?? 0) }

    /// Beat the clock: the window starts at T0, or at the actual ring time if the OS rang late.
    public var beatTheClockEndsAt: Date? {
        guard mode.modeType == .beatTheClock else { return nil }
        return max(t0Date, rangAtDate).addingTimeInterval(TimeInterval(mode.windowSeconds ?? 0))
    }

    public func snoozed(at now: Date) -> RingState {
        var copy = self
        copy.snoozesUsed += 1
        copy.snoozedUntil = ISOInstant.format(now.addingTimeInterval(TimeInterval((mode.snoozeMinutes ?? 5) * 60)))
        return copy
    }

    public func isExpired(at now: Date) -> Bool { deadline <= now }

    public var occurrence: Occurrence {
        Occurrence(occurrenceID: occurrenceId, alarmID: alarmId,
                   localDate: LocalDate(instant: t0Date, zone: .current), instant: t0Date, countsForChallenge: countsForChallenge)
    }

    public static func start(_ occurrence: Occurrence, schedule: AlarmSchedule, rangAt: Date, practice: Bool = false) -> RingState {
        RingState(occurrenceId: occurrence.occurrenceID, alarmId: schedule.id, label: schedule.label,
                  t0: ISOInstant.format(occurrence.instant), rangAt: ISOInstant.format(rangAt), mode: schedule.mode,
                  countsForChallenge: occurrence.countsForChallenge && !practice, practice: practice, soundId: schedule.sound.id)
    }
}

/// ISO-8601 instants exactly like Java's `Instant.toString()` for whole seconds ("2026-10-20T04:30:00Z").
public enum ISOInstant {
    public static func format(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    public static func parse(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string)
    }
}
