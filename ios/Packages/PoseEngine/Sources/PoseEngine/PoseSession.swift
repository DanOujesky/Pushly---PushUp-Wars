@preconcurrency import AVFoundation
import Core
import CoreMotion
import Foundation
@preconcurrency import MediaPipeTasksVision
import RepEngine

/// What the camera session reports to the UI besides pose frames.
public struct PoseSessionStatus: Sendable, Equatable {
    public var fps: Double = 0
    public var model: PoseModel = .full
    public var tooDark = false
    public var imageWidth: Double = 720
    public var imageHeight: Double = 1280
    public var personVisible = false
    /// A second person is in the frame (doc 06 §2.2) — counting pauses until they leave.
    public var multiplePeople = false

    public init() {}
}

public enum PoseModel: String, Sendable {
    case full = "pose_landmarker_full"
    case lite = "pose_landmarker_lite"
}

/// Camera → MediaPipe Pose Landmarker (LIVE_STREAM, 1 pose, CPU) → `PoseFrame` (doc 05 §3), plus device motion for
/// the anti-cheat check (doc 06 §2.1). Switches to the lite model when the full one is too slow or the phone is hot
/// (doc 05 §7). Frames and status are delivered on the main actor.
public final class PoseSession: NSObject, PoseLandmarkerLiveStreamDelegate, @unchecked Sendable {
    public let camera: CameraSource
    private let lock = NSLock()
    private var landmarker: PoseLandmarker?
    /// Image-mode lite landmarker with 2 poses, run on every 30th frame to spot a second person (doc 06 §2.2).
    private var peopleChecker: PoseLandmarker?
    private var model: PoseModel = .full
    private var status = PoseSessionStatus()
    private var frameTimes: [Int] = []
    private var slowSince: Int?
    private var darkSince: Int?
    private var frameCounter = 0
    private var lastTimestamp = -1
    private let motion = MotionMonitor()
    /// Physical orientation from gravity; frames follow it so push-ups also count with the phone on its side.
    private let onFrame: @MainActor @Sendable (PoseFrame, CGSize) -> Void
    private let onStatus: @MainActor @Sendable (PoseSessionStatus) -> Void
    private var thermalObserver: NSObjectProtocol?

    public init(position: AVCaptureDevice.Position = .front,
                onFrame: @escaping @MainActor @Sendable (PoseFrame, CGSize) -> Void,
                onStatus: @escaping @MainActor @Sendable (PoseSessionStatus) -> Void) {
        camera = CameraSource(position: position)
        self.onFrame = onFrame
        self.onStatus = onStatus
        super.init()
        camera.onFrame = { [weak self] buffer in self?.handle(buffer) }
    }

    /// Loads the model ahead of time (e.g. while the alarm screen is shown) — doc 05 §7 pre-warm.
    public func prewarm() {
        lock.withLock {
            if landmarker == nil { landmarker = makeLandmarker(Self.preferredModel()) }
            if peopleChecker == nil { peopleChecker = makePeopleChecker() }
        }
    }

    public func start() async throws {
        prewarm()
        motion.start()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.applyThermalState() }
        applyThermalState()
        try await camera.start()
    }

    public func stop() {
        camera.stop()
        motion.stop()
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        thermalObserver = nil
    }

    // MARK: Model

    static func preferredModel() -> PoseModel {
        ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue ? .lite : .full
    }

    private func makeLandmarker(_ m: PoseModel) -> PoseLandmarker? {
        guard let path = Bundle.main.path(forResource: m.rawValue, ofType: "task") else {
            PLog.error("Pose model \(m.rawValue).task missing from the app bundle", .pose)
            return nil
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.shouldOutputSegmentationMasks = false
        options.poseLandmarkerLiveStreamDelegate = self
        do {
            model = m
            status.model = m
            return try PoseLandmarker(options: options)
        } catch {
            PLog.error("PoseLandmarker init failed: \(error)", .pose)
            return nil
        }
    }

    private func makePeopleChecker() -> PoseLandmarker? {
        guard let path = Bundle.main.path(forResource: PoseModel.lite.rawValue, ofType: "task") else { return nil }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .image
        options.numPoses = 2
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.shouldOutputSegmentationMasks = false
        return try? PoseLandmarker(options: options)
    }

    /// True when the checker sees two people with a solid second pose.
    private func checkPeople(_ image: MPImage) {
        guard let checker = lock.withLock({ peopleChecker }), let result = try? checker.detect(image: image) else { return }
        var two = false
        if result.landmarks.count >= 2 {
            let second = result.landmarks[1]
            let presence = second.compactMap { $0.presence?.doubleValue }.reduce(0, +) / Double(max(second.count, 1))
            two = presence >= 0.5
        }
        if two != status.multiplePeople {
            status.multiplePeople = two
            publishStatus()
        }
    }

    private func switchToLite(reason: String) {
        lock.withLock {
            guard model == .full else { return }
            PLog.info("Switching to the lite pose model: \(reason)", .pose)
            landmarker = makeLandmarker(.lite)
            frameTimes = []
        }
    }

    private func applyThermalState() {
        let serious = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        if serious {
            switchToLite(reason: "thermal state")
            camera.setFrameRate(15)
        }
    }

    // MARK: Frames

    private func handle(_ buffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        let ms = Int(CMTimeGetSeconds(pts) * 1000)
        guard ms > lastTimestamp else { return }
        lastTimestamp = ms
        frameCounter += 1
        if frameCounter % 10 == 0, let pixels = CMSampleBufferGetImageBuffer(buffer) {
            let luma = FrameQuality.meanLuma(pixels) ?? 1
            darkSince = luma < 0.12 ? (darkSince ?? ms) : nil
            let dark = darkSince.map { ms - $0 >= 2000 } ?? false
            if dark != status.tooDark {
                status.tooDark = dark
                publishStatus()
            }
        }
        if let pixels = CMSampleBufferGetImageBuffer(buffer) {
            status.imageWidth = Double(CVPixelBufferGetWidth(pixels))
            status.imageHeight = Double(CVPixelBufferGetHeight(pixels))
        }
        guard let landmarker = lock.withLock({ landmarker }), let image = try? MPImage(sampleBuffer: buffer) else { return }
        if frameCounter % 30 == 0 { checkPeople(image) }
        try? landmarker.detectAsync(image: image, timestampInMilliseconds: ms)
    }

    public func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?,
                               timestampInMilliseconds: Int, error: Error?) {
        trackFps(timestampInMilliseconds)
        guard let result, let lms = result.landmarks.first, let world = result.worldLandmarks.first,
              lms.count == 33, world.count == 33 else {
            if status.personVisible {
                status.personVisible = false
                publishStatus()
            }
            return
        }
        let frame = PoseFrame(
            tMs: Int64(timestampInMilliseconds),
            landmarks: lms.map {
                PoseLandmark(x: Double($0.x), y: Double($0.y), z: Double($0.z),
                             visibility: $0.visibility?.doubleValue ?? 0, presence: $0.presence?.doubleValue ?? 0)
            },
            world: world.map { WorldPoint(x: Double($0.x), y: Double($0.y), z: Double($0.z)) },
            motion: motion.rms()
        )
        if !status.personVisible {
            status.personVisible = true
            publishStatus()
        }
        let deliver = onFrame
        let size = CGSize(width: status.imageWidth, height: status.imageHeight)
        Task { @MainActor in deliver(frame, size) }
    }

    private func trackFps(_ ms: Int) {
        frameTimes.append(ms)
        if frameTimes.count > 30 { frameTimes.removeFirst() }
        guard frameTimes.count >= 10, let first = frameTimes.first, let last = frameTimes.last, last > first else { return }
        let fps = Double(frameTimes.count - 1) * 1000 / Double(last - first)
        status.fps = fps
        // Lite model if the full one stays under 15 fps for 3 s (doc 05 §3).
        if fps < RepEngineConstants.liteModelBelowFps {
            slowSince = slowSince ?? ms
            if let since = slowSince, ms - since >= RepEngineConstants.liteModelAfterMs { switchToLite(reason: "fps \(Int(fps))") }
        } else {
            slowSince = nil
        }
        if frameTimes.count % 15 == 0 { publishStatus() }
    }

    private func publishStatus() {
        let s = status
        let deliver = onStatus
        Task { @MainActor in deliver(s) }
    }
}

/// Generated performance constants (shared/rep-engine-spec) re-exported for the camera layer.
enum RepEngineConstants {
    static let liteModelBelowFps = PushupSpecV2.Performance.liteModelBelowFps
    static let liteModelAfterMs = PushupSpecV2.Performance.liteModelAfterMs
}

/// Device motion RMS (user acceleration, g) over the last second, sampled at 50 Hz (doc 06 §2.1).
final class MotionMonitor: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let lock = NSLock()
    private var samples: [Double] = []
    private var lastGravity: CMAcceleration?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] data, _ in
            guard let a = data?.userAcceleration, let self else { return }
            let m = a.x * a.x + a.y * a.y + a.z * a.z
            let gravity = data?.gravity
            self.lock.withLock {
                self.lastGravity = gravity
                self.samples.append(m)
                if self.samples.count > 50 { self.samples.removeFirst() }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Latest gravity vector (device coordinates, g).
    func gravity() -> CMAcceleration? {
        lock.withLock { lastGravity }
    }

    func rms() -> Double? {
        lock.withLock {
            samples.isEmpty ? nil : (samples.reduce(0, +) / Double(samples.count)).squareRoot()
        }
    }
}
