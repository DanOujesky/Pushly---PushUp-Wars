import Core
import Foundation

/// What camera sessions need from the backend, bundled for injection: the rep-log outbox, the server clock anchor
/// and the app version. Nil-safe: without a backend (guest builds) sessions still work, nothing is uploaded.
@MainActor
public final class SessionServices {
    public let uploader: SessionUploader
    public let appVersion: String
    public let summary: (@Sendable () async throws -> Data)?
    private let fetchServerMs: (@Sendable () async throws -> Int64)?
    private let clock: any AppClock

    public init(uploader: SessionUploader, appVersion: String, clock: any AppClock = SystemClock(),
                fetchServerMs: (@Sendable () async throws -> Int64)?, summary: (@Sendable () async throws -> Data)?) {
        self.uploader = uploader
        self.appVersion = appVersion
        self.clock = clock
        self.fetchServerMs = fetchServerMs
        self.summary = summary
    }

    /// Server clock anchor, at most 3 s of waiting; nil offline (the server then checks the wall clock, D-044).
    public func anchor() async -> ServerAnchor? {
        guard let fetch = fetchServerMs else { return nil }
        let clock = clock
        return await withTaskGroup(of: ServerAnchor?.self) { group in
            group.addTask { try? await ServerAnchor.measure(monotonic: { clock.monotonicMs() }, fetch: fetch) }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Queues a finished free-training session (counts for totals, never for the wake streak).
    public func submitTraining(_ model: RepSessionModel, anchor: ServerAnchor?) -> String {
        let id = UUID().uuidString.lowercased()
        uploader.enqueue(model.repLog(sessionId: id, context: "training", anchor: anchor, appVersion: appVersion))
        return id
    }
}
