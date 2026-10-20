import AlarmDomain
import Core
import Foundation

/// Uploads the alarm outbox to the server and restores alarms from it (roadmap P2-09). Only when signed in; alarms
/// never depend on it (CLAUDE.md §4.4). Throttled: runs when something is queued, or at most every 6 h to restore.
@MainActor
public final class AlarmSyncCoordinator {
    public typealias Transport = @Sendable (Data) async throws -> Data

    private let repository: AlarmRepository
    private let transport: () async -> Transport?
    private let now: @Sendable () -> Date
    private var lastFullSync: Date?
    private var running = false

    /// `transport` returns nil while signed out / in guest mode.
    public init(repository: AlarmRepository, now: @escaping @Sendable () -> Date = { Date() },
                transport: @escaping () async -> Transport?) {
        self.repository = repository
        self.transport = transport
        self.now = now
    }

    /// Returns true when the local alarms changed (restored or conflict resolved) and the scheduler must re-sync.
    @discardableResult
    public func syncIfNeeded(force: Bool = false) async -> Bool {
        guard !running else { return false }
        let due = force || !repository.document.outbox.isEmpty
            || lastFullSync.map { now().timeIntervalSince($0) > 6 * 3600 } ?? true
        guard due, let send = await transport() else { return false }
        running = true
        defer { running = false }
        let before = repository.alarms
        let (changes, sent) = AlarmSync.changes(for: repository.document)
        do {
            let body = try JSONEncoder().encode(changes)
            let data = try await send(body)
            let response = try JSONDecoder().decode(AlarmSync.Response.self, from: data)
            repository.applySync(sent: sent, response: response)
            lastFullSync = now()
            return repository.alarms != before
        } catch {
            // Offline or server down: keep the outbox, try again next time. Alarms keep working locally.
            PLog.warning("Alarm sync failed: \(error)", .sync)
            return false
        }
    }
}
