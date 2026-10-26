@preconcurrency import AVFoundation
import Core
import Foundation

/// Camera access state, mirrored for the UI's pre-permission explainer (CLAUDE.md §10).
public enum CameraAuthorization: Sendable {
    case notDetermined, denied, authorized

    public static var current: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public static func request() async -> CameraAuthorization {
        await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    }
}

/// Front (default) or rear camera, 1280×720 @ 30 fps, BGRA, latest frame only (doc 05 §2). Frames are rotated
/// upright for the current device orientation and NOT mirrored, so the engine always sees un-mirrored coordinates.
public final class CameraSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let session = AVCaptureSession()
    public private(set) var position: AVCaptureDevice.Position
    /// Called on the capture queue with every frame that wasn't dropped.
    var onFrame: ((CMSampleBuffer) -> Void)?
    /// Second consumer of the same frames (battle video, doc 07 §5: never open the camera twice). Upright, un-mirrored.
    public var videoTap: (@Sendable (CMSampleBuffer) -> Void)? {
        get { tapLock.withLock { tap } }
        set { tapLock.withLock { tap = newValue } }
    }
    private let tapLock = NSLock()
    private var tap: (@Sendable (CMSampleBuffer) -> Void)?

    private let queue = DispatchQueue(label: "app.pushly.camera", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var configured = false
    /// Rotation from gravity (CoreMotion). Works with the iOS rotation lock on, where the UI — and the rotation
    /// coordinator — stay portrait while the phone lies sideways for push-ups. Wins over the coordinator once known.
    private var gravityAngle: CGFloat?

    public init(position: AVCaptureDevice.Position = .front) {
        self.position = position
        super.init()
    }

    /// Configures (once) and starts the session. Throws if no camera is available.
    public func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.configured { try self.configure() }
                    if !self.session.isRunning { self.session.startRunning() }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Lowers the frame rate (thermal pressure, doc 05 §7).
    public func setFrameRate(_ fps: Int32) {
        queue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            let duration = CMTime(value: 1, timescale: fps)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .vga640x480
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video) else {
            throw AppError(code: .unknown, message: "no camera")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw AppError(code: .unknown, message: "camera input refused") }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw AppError(code: .unknown, message: "camera output refused") }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if (try? device.lockForConfiguration()) != nil {
            if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = true }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }
        self.device = device
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotation = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] c, _ in
            guard let self else { return }
            let angle = c.videoRotationAngleForHorizonLevelCapture
            self.queue.async { if self.gravityAngle == nil { self.applyRotation(angle) } }
        }
        configured = true
    }

    /// Physical orientation from gravity → frames upright for how the phone really stands (portrait or on its side).
    func setGravityOrientation(_ orientation: PhysicalOrientation) {
        queue.async {
            let angle = orientation.videoRotationAngle
            guard self.gravityAngle != angle else { return }
            self.gravityAngle = angle
            self.applyRotation(angle)
        }
    }

    private func applyRotation(_ angle: CGFloat) {
        guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
        videoTap?(sampleBuffer)
    }
}

/// Mean luma of a BGRA frame from a sparse grid (cheap, every 10th frame) — "Turn on a light" hint (doc 05 §2).
enum FrameQuality {
    static func meanLuma(_ buffer: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0
        var n = 0
        for y in stride(from: h / 16, to: h, by: max(h / 8, 1)) {
            for x in stride(from: w / 16, to: w, by: max(w / 8, 1)) {
                let o = y * row + x * 4
                sum += 0.114 * Double(p[o]) + 0.587 * Double(p[o + 1]) + 0.299 * Double(p[o + 2])
                n += 1
            }
        }
        return n > 0 ? sum / Double(n) / 255.0 : nil
    }
}

/// How the phone physically stands, from gravity (rotation lock doesn't matter).
public enum PhysicalOrientation: Sendable, Equatable {
    case portrait, upsideDown, landscapeLeft, landscapeRight

    /// Capture-connection angle that makes frames upright (same for the front and back camera; the sensor's native
    /// orientation is landscape with the top of the phone on the left).
    var videoRotationAngle: CGFloat {
        switch self {
        case .portrait: 90
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .upsideDown: 270
        }
    }

    /// Gravity in device coordinates (portrait upright: y ≈ −1). Needs a clear tilt (> 0.55 g along an axis) to change,
    /// so a phone leaning back on the floor keeps its last orientation; nil = keep the current one.
    public static func from(gravityX x: Double, gravityY y: Double, current: PhysicalOrientation?) -> PhysicalOrientation? {
        let threshold = 0.55
        if abs(x) < threshold && abs(y) < threshold { return current }
        if abs(y) >= abs(x) { return y < 0 ? .portrait : .upsideDown }
        return x < 0 ? .landscapeLeft : .landscapeRight
    }
}
