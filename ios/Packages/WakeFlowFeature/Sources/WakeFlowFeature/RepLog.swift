import Foundation
import RepEngine

/// The rep log uploaded to submit-rep-session (shared/contracts/rep-log.schema.json, doc 06 §3). Same JSON as Android.
/// Rep / set times are milliseconds since the session start on the monotonic clock.
public struct RepLog: Codable, Hashable, Sendable {
    public struct Context: Codable, Hashable, Sendable {
        public var type: String
        public var occurrenceId: String?
    }

    public struct Anchor: Codable, Hashable, Sendable {
        public var serverTime: String
        public var monotonicAtAnchorMs: Int64
    }

    public struct Timing: Codable, Hashable, Sendable {
        public var monotonicStartMs: Int64
        public var monotonicEndMs: Int64
        public var wallStart: String
        public var serverAnchor: Anchor?
        public var ringStartedAtMonotonicMs: Int64?
    }

    public struct Rep: Codable, Hashable, Sendable {
        public var i: Int
        public var tStartMs: Int64
        public var tBottomMs: Int64
        public var tEndMs: Int64
        public var quality: Int
        public var minElbow: Double?
        public var maxElbow: Double?
        public var minBodyLine: Double?
        public var depth: Double?
    }

    public struct SetSpan: Codable, Hashable, Sendable {
        public var startMs: Int64
        public var endMs: Int64
    }

    public struct Suspicion: Codable, Hashable, Sendable {
        public var replay: Double
        public var motion: Double
        public var continuity: Double
        public var liveness: String
    }

    public var sessionId: String
    public var deviceId: String?
    public var context: Context
    public var specVersion: Int
    public var appVersion: String
    public var platform: String
    public var deviceModel: String
    public var timing: Timing
    /// completed | gaveUp | expired
    public var outcome: String
    public var snoozes: Int
    public var sprintStartMs: Int64?
    public var sets: [SetSpan]
    public var reps: [Rep]
    public var rejected: [String: Int]
    /// 10 Hz feature trace (SessionMonitor): JSON, raw deflate, base64 — never video.
    public var featureTrace: String?
    public var suspicion: Suspicion
    public var signature: String?
}

/// Server anchor for rep timestamps: server epoch ms at a monotonic instant (doc 06 §3, T5 clock tampering).
public struct ServerAnchor: Sendable, Equatable {
    public let serverMs: Int64
    public let monotonicMs: Int64

    public init(serverMs: Int64, monotonicMs: Int64) {
        self.serverMs = serverMs
        self.monotonicMs = monotonicMs
    }

    /// Measures one round trip and assumes the server read its clock half way.
    public static func measure(monotonic: () -> Int64, fetch: () async throws -> Int64) async throws -> ServerAnchor {
        let before = monotonic()
        let server = try await fetch()
        let after = monotonic()
        return ServerAnchor(serverMs: server, monotonicMs: before + (after - before) / 2)
    }
}

/// Collects the timeline of one camera session on the monotonic clock: reps (converted from camera frame time),
/// set and sprint markers. Pure value type — RepSessionModel owns one; tests drive it directly.
public struct RepTimeline: Sendable, Equatable {
    public private(set) var monotonicStartMs: Int64
    public private(set) var wallStart: Date
    public private(set) var monotonicEndMs: Int64?
    /// monotonic − camera frame time, measured at the first frame (camera clocks differ per device).
    public private(set) var frameOffsetMs: Int64?
    public private(set) var reps: [RepLog.Rep] = []
    public private(set) var sets: [RepLog.SetSpan] = []
    public private(set) var sprintStartMs: Int64?
    private var openSetStart: Int64?

    public init(monotonicStartMs: Int64, wallStart: Date) {
        self.monotonicStartMs = monotonicStartMs
        self.wallStart = wallStart
    }

    public mutating func frame(tMs: Int64, monotonicNow: Int64) {
        if frameOffsetMs == nil { frameOffsetMs = monotonicNow - tMs }
    }

    /// Session-relative ms of a camera frame time (the same clock as reps, sets and the feature trace).
    public func relative(_ frameMs: Int64) -> Int64 { max(0, frameMs + (frameOffsetMs ?? 0) - monotonicStartMs) }

    private func rel(_ frameMs: Int64) -> Int64 { relative(frameMs) }

    public mutating func counted(_ rep: CountedRep, index: Int) {
        reps.append(RepLog.Rep(i: index, tStartMs: rel(rep.tStart), tBottomMs: rel(rep.tBottom), tEndMs: rel(rep.tEnd),
                               quality: rep.quality, minElbow: round1(rep.minElbow), maxElbow: round1(rep.maxElbow),
                               minBodyLine: round1(rep.minBodyLine), depth: (rep.depth * 1000).rounded() / 1000))
    }

    public mutating func startSet(monotonicNow: Int64) { openSetStart = monotonicNow - monotonicStartMs }

    public mutating func endSet(monotonicNow: Int64) {
        guard let start = openSetStart else { return }
        sets.append(RepLog.SetSpan(startMs: start, endMs: max(start, monotonicNow - monotonicStartMs)))
        openSetStart = nil
    }

    /// A finished set, in session-relative ms (sets mode: first rep start → last rep end).
    public mutating func appendSet(startMs: Int64, endMs: Int64) {
        sets.append(RepLog.SetSpan(startMs: startMs, endMs: max(startMs, endMs)))
    }

    public mutating func startSprint(monotonicNow: Int64) {
        if sprintStartMs == nil { sprintStartMs = monotonicNow - monotonicStartMs }
    }

    public mutating func end(monotonicNow: Int64) {
        if openSetStart != nil { endSet(monotonicNow: monotonicNow) }
        if monotonicEndMs == nil { monotonicEndMs = max(monotonicNow, monotonicStartMs + (reps.last?.tEndMs ?? 0)) }
    }

    private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    /// Builds the upload. `ringAtMonotonicMs`: when the alarm rang, on the same monotonic clock (wake only).
    public func log(sessionId: String, context: String, occurrenceId: String?, outcome: String, snoozes: Int,
                    rejected: [RejectReason: Int], anchor: ServerAnchor?, ringAtMonotonicMs: Int64?,
                    appVersion: String, deviceModel: String, motionSuspicion: Double,
                    monitor: SessionMonitor? = nil) -> RepLog {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return RepLog(
            sessionId: sessionId, deviceId: nil, context: .init(type: context, occurrenceId: occurrenceId),
            specVersion: RepEngineInfo.specVersion, appVersion: appVersion, platform: "ios", deviceModel: deviceModel,
            timing: .init(monotonicStartMs: monotonicStartMs, monotonicEndMs: monotonicEndMs ?? monotonicStartMs,
                          wallStart: f.string(from: wallStart),
                          serverAnchor: anchor.map {
                              .init(serverTime: f.string(from: Date(timeIntervalSince1970: Double($0.serverMs) / 1000)),
                                    monotonicAtAnchorMs: $0.monotonicMs)
                          },
                          ringStartedAtMonotonicMs: ringAtMonotonicMs.map { max(0, $0) }),
            outcome: outcome, snoozes: snoozes, sprintStartMs: sprintStartMs, sets: sets, reps: reps,
            rejected: Dictionary(uniqueKeysWithValues: rejected.map { ($0.key.rawValue, $0.value) }),
            featureTrace: monitor?.encodedTrace,
            suspicion: .init(replay: monitor?.replay ?? 0, motion: min(max(motionSuspicion, 0), 1),
                             continuity: monitor?.continuity ?? 0, liveness: "n/a"),
            signature: nil)
    }
}
