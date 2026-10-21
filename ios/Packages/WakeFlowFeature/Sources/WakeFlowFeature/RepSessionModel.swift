import AVFoundation
import Core
import Foundation
import Observation
import PoseEngine
import RepEngine
import UIKit

/// One camera push-up session (doc 05): feeds pose frames into `RepEngine`, keeps the count, hints and guidance.
/// Pure state logic is testable by feeding frames directly (`ingest`); the camera is attached by `start()`.
@MainActor
@Observable
public final class RepSessionModel {
    public enum Mode: Equatable, Sendable {
        /// Wake challenge: count up to `target`, then `onFinished`.
        case wake(target: Int)
        /// Free training (PS-80): count until the user ends the session.
        case training
        /// Counting only; the owner decides when it is over (wake modes sprint / sets drive it themselves).
        case open
    }

    /// Replaces the big counter (e.g. "7 / 10" of the current set, sprint seconds left).
    public struct CounterDisplay: Equatable, Sendable {
        public var value: String
        public var caption: String
        public var progress: Double?

        public init(value: String, caption: String, progress: Double? = nil) {
            self.value = value
            self.caption = caption
            self.progress = progress
        }
    }

    public struct Summary: Equatable, Sendable {
        public let reps: Int
        public let averageQuality: Int
        public let rejected: [RejectReason: Int]
        public let durationSeconds: Int
    }

    public let mode: Mode
    public private(set) var counted = 0
    public private(set) var lastQuality: Int?
    public private(set) var hint: HintGate.Hint?
    public private(set) var guidance: Guidance = .stepIntoFrame
    public private(set) var state: RepState = .notReady
    public private(set) var landmarks: [PoseLandmark] = []
    public private(set) var status = PoseSessionStatus()
    public private(set) var cameraError: String?
    public private(set) var finished = false
    public private(set) var outcome = "completed"
    public var speakCount: Bool
    public var display: CounterDisplay?
    /// Rep / set / sprint times on the monotonic clock — becomes the uploaded rep log (doc 06 §3).
    public private(set) var timeline: RepTimeline?
    /// Feed continuity, limb-length wobble and the 10 Hz feature trace (doc 06 §2).
    public private(set) var monitor = SessionMonitor()
    /// Called on every counted rep with the session total (wake modes react to it).
    public var onCounted: ((Int) -> Void)?

    private var engine: RepEngine?
    /// Reps counted by earlier engines of this session (a rotation changes the image size → new engine).
    private var countedBefore = 0
    private var gate = HintGate()
    private var qualities: [Int] = []
    private var rejected: [RejectReason: Int] = [:]
    private var startedAt = Date()
    private var session: PoseSession?
    private let speech = AVSpeechSynthesizer()
    private let haptics = UIImpactFeedbackGenerator(style: .heavy)
    private let onFinished: (Summary) -> Void
    private let clock: any AppClock
    /// Debug builds only: raw frames for the pose recorder (P3-04).
    public private(set) var recorder: PoseRecorder?

    public init(mode: Mode, speakCount: Bool = false, record: Bool = false, clock: any AppClock = SystemClock(),
                onFinished: @escaping (Summary) -> Void) {
        self.mode = mode
        self.speakCount = speakCount
        self.onFinished = onFinished
        self.clock = clock
        startedAt = clock.now()
        #if DEBUG
        if record { recorder = PoseRecorder() }
        #endif
    }

    public var target: Int? {
        if case let .wake(t) = mode { return t }
        return nil
    }

    public var remaining: Int? { target.map { max($0 - counted, 0) } }

    public var summary: Summary {
        Summary(reps: counted,
                averageQuality: qualities.isEmpty ? 0 : Int((Double(qualities.reduce(0, +)) / Double(qualities.count)).rounded()),
                rejected: rejected,
                durationSeconds: Int(clock.now().timeIntervalSince(startedAt)))
    }

    // MARK: Camera

    public func prewarm() {
        makeSession().prewarm()
    }

    public func start() async {
        beginTimeline()
        do {
            try await makeSession().start()
            cameraError = nil
        } catch {
            cameraError = String(localized: "The camera couldn't start. Close other apps that use it and try again.")
            PLog.error("Camera start failed: \(error)", .camera)
        }
    }

    public func stop() {
        session?.stop()
    }

    public var captureSession: AVCaptureSession? { session?.camera.session }

    private func makeSession() -> PoseSession {
        if let session { return session }
        let s = PoseSession(onFrame: { [weak self] frame, size in self?.ingest(frame, imageSize: size) },
                            onStatus: { [weak self] status in self?.update(status) })
        session = s
        return s
    }

    private func update(_ s: PoseSessionStatus) {
        status = s
        refreshGuidance()
    }

    // MARK: Frames

    /// Feeds one pose frame (from the camera, or from a test). `imageSize` = upright frame size in pixels.
    public func ingest(_ frame: PoseFrame, imageSize: CGSize) {
        guard !finished else { return }
        // Someone else in the frame: pause counting until they leave (doc 06 §2.2).
        if status.multiplePeople {
            landmarks = frame.landmarks
            return
        }
        let engine: RepEngine
        if let current = self.engine, current.imageWidth == imageSize.width, current.imageHeight == imageSize.height {
            engine = current
        } else {
            countedBefore = counted
            engine = RepEngine(imageWidth: imageSize.width, imageHeight: imageSize.height)
            self.engine = engine
        }
        landmarks = frame.landmarks
        recorder?.append(frame, imageSize: imageSize)
        if timeline == nil { timeline = RepTimeline(monotonicStartMs: clock.monotonicMs(), wallStart: clock.now()) }
        timeline?.frame(tMs: frame.tMs, monotonicNow: clock.monotonicMs())
        let events = engine.process(frame)
        if let tl = timeline { monitor.frame(frame, features: engine.lastFeatures, relativeMs: tl.relative(frame.tMs)) }
        for event in events {
            switch event {
            case let .counted(rep):
                counted = countedBefore + rep.index
                lastQuality = rep.quality
                qualities.append(rep.quality)
                timeline?.counted(rep, index: counted)
                hint = nil
                haptics.impactOccurred()
                announce(rep.index)
            case let .rejected(reason, t):
                rejected[reason, default: 0] += 1
                if let h = gate.offer(reason, at: t) { hint = h }
            }
        }
        state = engine.state
        refreshGuidance()
        if counted != countedNotified {
            countedNotified = counted
            onCounted?(counted)
        }
        if let target, counted >= target { finish() }
    }

    private var countedNotified = 0

    // MARK: Markers (wake modes)

    public func markSetStart() { timeline?.startSet(monotonicNow: clock.monotonicMs()) }
    public func markSetEnd() { timeline?.endSet(monotonicNow: clock.monotonicMs()) }
    /// Starts the session clock (camera start; tests call it directly).
    public func beginTimeline() {
        startedAt = clock.now()
        if timeline == nil { timeline = RepTimeline(monotonicStartMs: clock.monotonicMs(), wallStart: startedAt) }
    }

    public func appendSet(startMs: Int64, endMs: Int64) { timeline?.appendSet(startMs: startMs, endMs: endMs) }
    public func markSprintStart() { timeline?.startSprint(monotonicNow: clock.monotonicMs()) }
    public var monotonicNowMs: Int64 { clock.monotonicMs() }
    public var nowDate: Date { clock.now() }

    /// The upload for this session (after `finish`). `ringAt`: when the alarm rang (wake only).
    public func repLog(sessionId: String, context: String, occurrenceId: String? = nil, snoozes: Int = 0,
                       anchor: ServerAnchor? = nil, ringAt: Date? = nil, appVersion: String,
                       battleId: String? = nil) -> RepLog {
        let tl = timeline ?? RepTimeline(monotonicStartMs: clock.monotonicMs(), wallStart: clock.now())
        let ringMono = ringAt.map { clock.monotonicMs() - Int64(clock.now().timeIntervalSince($0) * 1000) }
        return tl.log(sessionId: sessionId, context: context, occurrenceId: occurrenceId, outcome: outcome,
                      snoozes: snoozes, rejected: rejected, anchor: anchor, ringAtMonotonicMs: ringMono,
                      appVersion: appVersion, deviceModel: Self.deviceModel, motionSuspicion: 0, monitor: monitor,
                      battleId: battleId)
    }

    public static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private func refreshGuidance() {
        guidance = Guidance.current(state: state, features: engine?.lastFeatures, personVisible: status.personVisible,
                                    tooDark: status.tooDark)
    }

    private func announce(_ n: Int) {
        guard speakCount else { return }
        let utterance = AVSpeechUtterance(string: "\(n)")
        utterance.rate = 0.55
        speech.speak(utterance)
    }

    /// Ends the session (target reached, the user ends training, gives up — `outcome` "gaveUp" — or time ran out).
    public func finish(outcome: String = "completed") {
        guard !finished else { return }
        finished = true
        self.outcome = outcome
        if timeline == nil { timeline = RepTimeline(monotonicStartMs: clock.monotonicMs(), wallStart: clock.now()) }
        timeline?.end(monotonicNow: clock.monotonicMs())
        stop()
        onFinished(summary)
    }
}

/// UI copy for engine codes (String Catalog keys; same English on Android in strings.xml).
public enum RepText {
    public static func hint(_ reason: RejectReason) -> String {
        switch reason {
        case .notDeepEnough: String(localized: "Go lower — chest close to the floor")
        case .noLockout: String(localized: "Push all the way up")
        case .hipsSagging: String(localized: "Tighten your core — hips up")
        case .hipsPiked: String(localized: "Lower your hips — straight line")
        case .kneesDown: String(localized: "Knees off the floor")
        case .bodyNotVisible: String(localized: "Move back — I need to see your whole body")
        case .tooFast: String(localized: "Control it — full reps only")
        case .tooSlow: String(localized: "Keep moving — that one took too long")
        case .irregularMotion: String(localized: "One smooth rep: down, then up")
        case .integrity: String(localized: "Tracking issue — keep the phone still")
        }
    }

    public static var onlyOnePerson: String { String(localized: "Only one person in frame") }

    public static func tip(_ reason: RejectReason) -> String {
        switch reason {
        case .notDeepEnough: String(localized: "Tip: lower until your elbows are bent past 90° and your chest nearly touches the floor.")
        case .hipsSagging, .hipsPiked: String(localized: "Tip: squeeze your glutes — shoulders, hips and ankles in one line.")
        case .kneesDown: String(localized: "Tip: only full push-ups count. Start with fewer reps if you need to.")
        default: hint(reason)
        }
    }

    public static func guidance(_ g: Guidance) -> String {
        switch g {
        case .stepIntoFrame: String(localized: "Step into the frame")
        case .turnPhoneToSide: String(localized: "Put the phone at your side, about 2 m away")
        case .showWholeBody: String(localized: "Move back — I need to see your whole body")
        case .moveBack: String(localized: "Move back a little")
        case .comeCloser: String(localized: "Come a bit closer")
        case .turnOnLight: String(localized: "Turn on a light")
        case .getIntoPlank: String(localized: "Get into the push-up position")
        case .ready: String(localized: "Go!")
        }
    }
}
