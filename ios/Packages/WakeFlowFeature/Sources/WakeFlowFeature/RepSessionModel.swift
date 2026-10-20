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
    public var speakCount: Bool

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

    public init(mode: Mode, speakCount: Bool = false, onFinished: @escaping (Summary) -> Void) {
        self.mode = mode
        self.speakCount = speakCount
        self.onFinished = onFinished
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
                durationSeconds: Int(Date().timeIntervalSince(startedAt)))
    }

    // MARK: Camera

    public func prewarm() {
        makeSession().prewarm()
    }

    public func start() async {
        startedAt = Date()
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
        let engine: RepEngine
        if let current = self.engine, current.imageWidth == imageSize.width, current.imageHeight == imageSize.height {
            engine = current
        } else {
            countedBefore = counted
            engine = RepEngine(imageWidth: imageSize.width, imageHeight: imageSize.height)
            self.engine = engine
        }
        landmarks = frame.landmarks
        for event in engine.process(frame) {
            switch event {
            case let .counted(rep):
                counted = countedBefore + rep.index
                lastQuality = rep.quality
                qualities.append(rep.quality)
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
        if let target, counted >= target { finish() }
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

    /// Ends the session (target reached, or the user ends free training).
    public func finish() {
        guard !finished else { return }
        finished = true
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
