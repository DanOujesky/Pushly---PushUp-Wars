import AVFoundation
import Core
import Foundation
import LiveKit
import Observation
import WakeFlowFeature

/// Battle video (doc 07 §5): joins the battle's LiveKit room, publishes my camera (the same frames MediaPipe gets —
/// the camera is never opened twice) and shows the opponent. Camera only, no microphone; nothing is recorded.
/// Without a token (video not configured, ghost / bot battles) the battle simply runs without video.
@MainActor
@Observable
public final class BattleVideo {
    public enum State: Equatable { case off, connecting, connected, unavailable }

    public private(set) var state: State = .off
    /// The opponent's camera, once subscribed.
    public private(set) var remoteTrack: (Track & VideoTrackProtocol)?
    /// My camera goes out (toggle in the battle HUD). Default on; off keeps watching the opponent.
    public private(set) var cameraOn = true

    private let room = Room()
    private var observer: RoomObserver?
    private var publication: LocalTrackPublication?
    private weak var reps: RepSessionModel?

    public init() {}

    struct Grant: Decodable {
        let url: String
        let token: String
    }

    public func start(battleId: String, service: BattleService, reps: RepSessionModel) async {
        guard state == .off else { return }
        self.reps = reps
        state = .connecting
        guard let data = try? await service.videoToken(battleId),
              let grant = try? JSONDecoder().decode(Grant.self, from: data) else {
            state = .unavailable
            return
        }
        let observer = RoomObserver { [weak self] track in
            Task { @MainActor in self?.remoteTrack = track }
        }
        room.delegates.add(delegate: observer)
        self.observer = observer
        do {
            try await room.connect(url: grant.url, token: grant.token)
            state = .connected
            if cameraOn { await publish() }
        } catch {
            PLog.warning("Battle video unavailable: \(error)", .battle)
            state = .unavailable
        }
    }

    public func toggleCamera() async {
        cameraOn.toggle()
        guard state == .connected else { return }
        if cameraOn {
            await publish()
        } else {
            await unpublish()
        }
    }

    public func stop() async {
        reps?.setVideoTap(nil)
        await room.disconnect()
        publication = nil
        remoteTrack = nil
        state = .off
    }

    private func publish() async {
        guard publication == nil, let reps else { return }
        let track = await LocalVideoTrack.createBufferTrack(
            name: Track.cameraName, source: .camera,
            options: BufferCaptureOptions(dimensions: Dimensions(width: 540, height: 960), fps: 15))
        guard let capturer = track.capturer as? BufferCapturer else { return }
        let gate = FrameGate()
        // Every other frame (≈ 15 fps): pose analysis keeps priority (doc 07 §5).
        reps.setVideoTap { buffer in
            if gate.take() { capturer.capture(buffer) }
        }
        // LiveKit needs a first frame to know the dimensions before publishing.
        try? await Task.sleep(for: .milliseconds(400))
        do {
            publication = try await room.localParticipant.publish(videoTrack: track)
        } catch {
            PLog.warning("Publishing battle video failed: \(error)", .battle)
            reps.setVideoTap(nil)
        }
    }

    private func unpublish() async {
        reps?.setVideoTap(nil)
        if let publication { try? await room.localParticipant.unpublish(publication: publication) }
        publication = nil
    }
}

/// Lets every other camera frame through (called on the camera queue only).
private final class FrameGate: @unchecked Sendable {
    private var n = 0

    func take() -> Bool {
        n += 1
        return n % 2 == 0
    }
}

/// LiveKit room events → the opponent's video track.
private final class RoomObserver: NSObject, RoomDelegate, @unchecked Sendable {
    private let onTrack: @Sendable ((Track & VideoTrackProtocol)?) -> Void

    init(onTrack: @escaping @Sendable ((Track & VideoTrackProtocol)?) -> Void) {
        self.onTrack = onTrack
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        if let track = publication.track as? (Track & VideoTrackProtocol) { onTrack(track) }
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        if publication.track is VideoTrackProtocol { onTrack(nil) }
    }
}
