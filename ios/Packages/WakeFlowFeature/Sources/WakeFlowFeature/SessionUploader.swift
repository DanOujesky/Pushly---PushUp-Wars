import Core
import Foundation
import Observation

/// Server answer to a rep session (shared/contracts/submit-rep-session.response.schema.json).
public struct SessionResult: Codable, Hashable, Sendable {
    public struct Wake: Codable, Hashable, Sendable {
        public var occurrenceId: String?
        public var status: String
        public var reason: String?
        public var points: Int?
        public var finalTargetReps: Int?
        public var score: Int?
        public var deadline: String?
    }

    public struct Streak: Codable, Hashable, Sendable {
        public var current: Int
        public var best: Int
        public var pureCurrent: Int
        public var pureBest: Int
        public var freezesAvailable: Int
        public var lastCountedDate: String?
    }

    public struct Totals: Codable, Hashable, Sendable {
        public var repsToday: Int?
        public var repsAllTime: Int?
    }

    public var sessionId: String
    public var verified: Bool
    public var late: Bool
    public var repsCounted: Int
    public var avgQuality: Int?
    public var wake: Wake?
    public var streak: Streak
    public var totals: Totals
}

/// Outbox for rep logs (doc 03 §5, roadmap P4-05): every finished session is written to disk first, then uploaded
/// when signed in and online. Retries with backoff (5 s → 15 min) while the error is retryable; logs the server
/// refuses for good (malformed, duplicate) are dropped. Results are kept so screens can show validated values
/// (PS-90). Works offline — the wake flow never waits for it (PS-34).
@MainActor
@Observable
public final class SessionUploader {
    public typealias Transport = @Sendable (Data) async throws -> Data

    public private(set) var pending: Set<String> = []
    public private(set) var results: [String: SessionResult] = [:]
    /// Newest validated result (Wake tab / result screens refresh from it).
    public private(set) var latest: SessionResult?

    private let directory: URL
    private let transport: () async -> Transport?
    private let sleep: @Sendable (Duration) async -> Void
    private var attempts = 0
    private var running = false

    public init(directory: URL, sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                transport: @escaping () async -> Transport?) {
        self.directory = directory
        self.transport = transport
        self.sleep = sleep
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        pending = Set(queued().map { $0.deletingPathExtension().lastPathComponent })
        if let data = try? Data(contentsOf: resultsFile),
           let saved = try? JSONDecoder().decode([String: SessionResult].self, from: data) {
            results = saved
        }
    }

    private var queueDir: URL { directory.appending(path: "queue") }
    private var resultsFile: URL { directory.appending(path: "results.json") }

    private func queued() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: [.creationDateKey]))
            ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Persists the log (atomic write) and starts an upload attempt in the background.
    public func enqueue(_ log: RepLog) {
        do {
            let data = try JSONEncoder().encode(log)
            // Name sorts by enqueue time so older sessions upload first.
            let name = "\(Int64(Date().timeIntervalSince1970 * 1000))-\(log.sessionId).json"
            try data.write(to: queueDir.appending(path: name), options: .atomic)
            pending.insert(name.replacingOccurrences(of: ".json", with: ""))
        } catch {
            PLog.error("Could not store rep log: \(error)", .sync)
        }
        Task { await flush() }
    }

    public func isPending(sessionId: String) -> Bool { pending.contains { $0.hasSuffix(sessionId) } }

    /// Uploads everything queued, oldest first. Stops on the first retryable failure and retries later.
    public func flush() async {
        guard !running else { return }
        running = true
        defer { running = false }
        while let file = queued().first {
            guard let send = await transport() else { return } // signed out / guest: keep the queue
            do {
                let response = try await send(try Data(contentsOf: file))
                let result = try JSONDecoder().decode(SessionResult.self, from: response)
                store(result)
                remove(file)
                attempts = 0
            } catch let error as AppError where !error.retryable && error.code != .unauthenticated {
                PLog.warning("Rep log dropped by the server (\(error.code.rawValue)): \(file.lastPathComponent)", .sync)
                remove(file)
            } catch is DecodingError {
                PLog.error("Unreadable server answer for \(file.lastPathComponent)", .sync)
                remove(file)
            } catch {
                attempts += 1
                let delay = min(5 * pow(3, Double(attempts - 1)), 900)
                PLog.warning("Rep log upload failed (retry in \(Int(delay)) s): \(error)", .sync)
                Task { [weak self] in
                    await self?.sleep(.seconds(delay))
                    await self?.flush()
                }
                return
            }
        }
    }

    private func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        pending.remove(file.deletingPathExtension().lastPathComponent)
    }

    private func store(_ result: SessionResult) {
        results[result.sessionId] = result
        latest = result
        if results.count > 50 {
            for key in results.keys.sorted().prefix(results.count - 50) { results[key] = nil }
        }
        if let data = try? JSONEncoder().encode(results) { try? data.write(to: resultsFile, options: .atomic) }
    }
}
