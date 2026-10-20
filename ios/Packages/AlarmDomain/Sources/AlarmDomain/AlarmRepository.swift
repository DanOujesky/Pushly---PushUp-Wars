import Foundation
import Observation

/// Everything the alarm system keeps on the device, as one JSON document (decision D-035): the user's alarms,
/// changes waiting for sync, and occurrences that are ringing right now. Same shape as Android `AlarmDocument`.
public struct AlarmDocument: Codable, Hashable, Sendable {
    public var schemaVersion: Int = 1
    public var alarms: [AlarmSchedule] = []
    public var outbox: [OutboxEntry] = []
    public var active: [RingState] = []
    /// Occurrences that ended (completed or given up) — their remaining nags must not re-ring. Newest last, max 50.
    public var finished: [String] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case schemaVersion, alarms, outbox, active, finished }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        alarms = try c.decodeIfPresent([AlarmSchedule].self, forKey: .alarms) ?? []
        outbox = try c.decodeIfPresent([OutboxEntry].self, forKey: .outbox) ?? []
        active = try c.decodeIfPresent([RingState].self, forKey: .active) ?? []
        finished = try c.decodeIfPresent([String].self, forKey: .finished) ?? []
    }
}

/// A change waiting for `sync-alarms` (P2-09). The newest entry per alarm wins.
public struct OutboxEntry: Codable, Hashable, Sendable {
    public var alarmId: String
    public var op: String
    public var version: Int
    public var queuedAt: String

    public static let upsert = "upsert"
    public static let delete = "delete"

    public init(alarmId: String, op: String, version: Int, queuedAt: String) {
        self.alarmId = alarmId
        self.op = op
        self.version = version
        self.queuedAt = queuedAt
    }
}

/// Reads and atomically writes the document (iOS: App Group container, shared with the widget extension).
public protocol DocumentStore: Sendable {
    func read() -> Data?
    func write(_ data: Data) throws
}

public final class InMemoryDocumentStore: DocumentStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    public init(_ data: Data? = nil) {
        self.data = data
    }

    public func read() -> Data? { lock.withLock { data } }
    public func write(_ data: Data) throws { lock.withLock { self.data = data } }
}

public struct FileDocumentStore: DocumentStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() -> Data? { try? Data(contentsOf: url) }

    public func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

public enum SaveResult: Equatable, Sendable {
    case saved(AlarmSchedule)
    case invalid(Set<String>)
    case tooManyAlarms
}

/// The single source of truth for alarms on the device. Works offline and without an account (CLAUDE.md §4.4).
/// Every mutation is persisted before it returns; the scheduler re-syncs from `alarms`. Mirrors Android `AlarmRepository`.
@MainActor
@Observable
public final class AlarmRepository {
    public private(set) var document: AlarmDocument
    public var alarms: [AlarmSchedule] { document.alarms }

    private let store: DocumentStore
    private let now: @Sendable () -> Date

    public init(store: DocumentStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
        document = store.read().flatMap { try? JSONDecoder().decode(AlarmDocument.self, from: $0) } ?? AlarmDocument()
    }

    private func commit(_ doc: AlarmDocument) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            try store.write(encoder.encode(doc))
        } catch {
            // Keep working from memory; the next successful write persists everything again.
            AlarmLog.sink?("Alarm document write failed: \(error)")
        }
        document = doc
    }

    public func alarm(id: String) -> AlarmSchedule? { document.alarms.first { $0.id == id } }

    /// Validates, bumps the version of an existing alarm, persists and queues it for sync.
    @discardableResult
    public func save(_ schedule: AlarmSchedule, zone: TimeZone = .current) -> SaveResult {
        var doc = document
        let today = LocalDate(instant: now(), zone: zone)
        let existing = doc.alarms.first { $0.id == schedule.id }
        if existing == nil, doc.alarms.count >= AlarmSchedule.maxAlarmsPerUser { return .tooManyAlarms }
        var cleaned = schedule
        cleaned.label = String(schedule.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AlarmSchedule.maxLabelLength))
        cleaned.overrides = schedule.overrides.filter { LocalDate($0.date).map { $0 >= today } ?? false }
        let errors = AlarmValidation.errors(cleaned, today: today)
        guard errors.isEmpty else { return .invalid(errors) }
        cleaned.version = (existing?.version ?? 0) + 1
        cleaned.updatedAt = ISOInstant.format(now())
        if let i = doc.alarms.firstIndex(where: { $0.id == cleaned.id }) {
            doc.alarms[i] = cleaned
        } else {
            doc.alarms.append(cleaned)
        }
        doc.outbox = queue(doc.outbox, id: cleaned.id, op: OutboxEntry.upsert, version: cleaned.version)
        commit(doc)
        return .saved(cleaned)
    }

    public func delete(id: String) {
        guard let existing = alarm(id: id) else { return }
        var doc = document
        doc.alarms.removeAll { $0.id == id }
        doc.outbox = queue(doc.outbox, id: id, op: OutboxEntry.delete, version: existing.version + 1)
        doc.active.removeAll { $0.alarmId == id }
        commit(doc)
    }

    @discardableResult
    public func setEnabled(id: String, _ enabled: Bool, zone: TimeZone = .current) -> SaveResult? {
        guard var s = alarm(id: id) else { return nil }
        s.enabled = enabled
        return save(s, zone: zone)
    }

    /// Skips the next ring (PS-24): adds a skip override for its local date.
    @discardableResult
    public func skipNext(id: String, zone: TimeZone = .current) -> SaveResult? {
        guard var s = alarm(id: id) else { return nil }
        if s.kind == .oneOff {
            s.enabled = false
            return save(s, zone: zone)
        }
        guard let next = AlarmOccurrences.next(of: s, from: now(), zone: zone) else { return nil }
        let date = next.localDate.description
        s.overrides.removeAll { $0.date == date }
        s.overrides.append(AlarmOverride(date: date, skip: true))
        return save(s, zone: zone)
    }

    @discardableResult
    public func unskip(id: String, date: String, zone: TimeZone = .current) -> SaveResult? {
        guard var s = alarm(id: id) else { return nil }
        s.overrides.removeAll { $0.date == date && $0.skip == true }
        return save(s, zone: zone)
    }

    /// Outbox entries the server accepted are removed (unless a newer change was queued meanwhile).
    public func acknowledge(_ entries: [OutboxEntry]) {
        var doc = document
        doc.outbox.removeAll { e in entries.contains { $0.alarmId == e.alarmId && $0.version >= e.version } }
        commit(doc)
    }

    // MARK: Ringing occurrences

    public var activeRings: [RingState] { document.active }

    public func putRing(_ state: RingState) {
        var doc = document
        doc.active.removeAll { $0.occurrenceId == state.occurrenceId }
        doc.active.append(state)
        commit(doc)
    }

    public func removeRing(occurrenceId: String) {
        guard document.active.contains(where: { $0.occurrenceId == occurrenceId }) else { return }
        var doc = document
        doc.active.removeAll { $0.occurrenceId == occurrenceId }
        commit(doc)
    }

    /// The occurrence ended (push-ups done or given up): stop tracking it and never re-ring it.
    public func finish(occurrenceId: String) {
        var doc = document
        doc.active.removeAll { $0.occurrenceId == occurrenceId }
        doc.finished.removeAll { $0 == occurrenceId }
        doc.finished.append(occurrenceId)
        if doc.finished.count > 50 { doc.finished.removeFirst(doc.finished.count - 50) }
        commit(doc)
    }

    /// Drops ring states whose deadline passed (they can no longer be completed).
    public func pruneRings(at date: Date? = nil) {
        let at = date ?? now()
        let kept = document.active.filter { !$0.isExpired(at: at) }
        guard kept.count != document.active.count else { return }
        var doc = document
        doc.active = kept
        commit(doc)
    }

    private func queue(_ outbox: [OutboxEntry], id: String, op: String, version: Int) -> [OutboxEntry] {
        outbox.filter { $0.alarmId != id } + [OutboxEntry(alarmId: id, op: op, version: version, queuedAt: ISOInstant.format(now()))]
    }
}

/// Logging hook for the domain package (the app routes it to PLog).
public enum AlarmLog {
    nonisolated(unsafe) public static var sink: (@Sendable (String) -> Void)?
}
