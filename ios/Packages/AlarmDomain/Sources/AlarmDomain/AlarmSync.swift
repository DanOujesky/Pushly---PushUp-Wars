import Foundation

/// Wire format of `sync_alarms` (supabase/migrations/…_alarms.sql, roadmap P2-09). Same as Android `AlarmSync`.
public enum AlarmSync {
    public struct Change: Codable, Equatable, Sendable {
        public var op: String
        public var alarm: AlarmSchedule?
        public var id: String?
        public var version: Int?
    }

    public struct Result: Codable, Equatable, Sendable {
        public var id: String?
        public var status: String
        public var version: Int?
        public var errors: [String]?
        public var server: AlarmSchedule?

        public init(id: String?, status: String, version: Int? = nil, errors: [String]? = nil, server: AlarmSchedule? = nil) {
            self.id = id
            self.status = status
            self.version = version
            self.errors = errors
            self.server = server
        }
    }

    public struct Response: Codable, Equatable, Sendable {
        public var results: [Result]
        public var alarms: [AlarmSchedule]

        public init(results: [Result], alarms: [AlarmSchedule]) {
            self.results = results
            self.alarms = alarms
        }
    }

    public static let maxChangesPerCall = 50

    /// The outbox as server changes (newest entry per alarm; upserts carry the current alarm).
    public static func changes(for document: AlarmDocument) -> (changes: [Change], sent: [OutboxEntry]) {
        var changes: [Change] = []
        var sent: [OutboxEntry] = []
        for entry in document.outbox.prefix(maxChangesPerCall) {
            if entry.op == OutboxEntry.delete {
                changes.append(Change(op: OutboxEntry.delete, alarm: nil, id: entry.alarmId, version: entry.version))
                sent.append(entry)
            } else if let alarm = document.alarms.first(where: { $0.id == entry.alarmId }) {
                changes.append(Change(op: OutboxEntry.upsert, alarm: alarm, id: nil, version: nil))
                sent.append(entry)
            } else {
                sent.append(entry) // alarm vanished locally without a delete entry: nothing to send, just clear it
            }
        }
        return (changes, sent)
    }
}

public extension AlarmRepository {
    /// Applies the server's answer (doc 12 §1): accepted changes leave the outbox and adopt the server version;
    /// conflicts take the newer server copy; invalid / over-limit changes are dropped (the device copy stays and keeps
    /// ringing locally); alarms only the server knows are restored (new phone / reinstall).
    func applySync(sent: [OutboxEntry], response: AlarmSync.Response) {
        var doc = document
        let sentByID = Dictionary(sent.map { ($0.alarmId, $0) }, uniquingKeysWith: { _, b in b })
        var done: [OutboxEntry] = []
        for r in response.results {
            guard let id = r.id?.lowercased(), let entry = sentByID.first(where: { $0.key.lowercased() == id })?.value else { continue }
            let stillCurrent = doc.outbox.contains { $0.alarmId == entry.alarmId && $0.version == entry.version }
            switch r.status {
            case "ok":
                if stillCurrent, let v = r.version, let i = doc.alarms.firstIndex(where: { $0.id == entry.alarmId }) {
                    doc.alarms[i].version = max(doc.alarms[i].version, v)
                }
                done.append(entry)
            case "conflict":
                if stillCurrent, let server = r.server, let i = doc.alarms.firstIndex(where: { $0.id == entry.alarmId }) {
                    doc.alarms[i] = server
                }
                done.append(entry)
            default: // invalid, limit, notFound
                AlarmLog.sink?("sync_alarms \(r.status) for \(entry.alarmId): \(r.errors ?? [])")
                done.append(entry)
            }
        }
        // Upserts whose alarm vanished locally were never sent: clear them as well.
        for e in sent where e.op != OutboxEntry.delete && !doc.alarms.contains(where: { $0.id == e.alarmId }) {
            done.append(e)
        }
        doc.outbox.removeAll { e in done.contains { $0.alarmId == e.alarmId && $0.version >= e.version } }

        let pendingDeletes = Set(doc.outbox.filter { $0.op == OutboxEntry.delete }.map { $0.alarmId.lowercased() })
        let local = Set(doc.alarms.map { $0.id.lowercased() })
        for server in response.alarms where !local.contains(server.id.lowercased()) && !pendingDeletes.contains(server.id.lowercased()) {
            guard doc.alarms.count < AlarmSchedule.maxAlarmsPerUser else { break }
            doc.alarms.append(server)
        }
        replaceDocument(doc)
    }
}
