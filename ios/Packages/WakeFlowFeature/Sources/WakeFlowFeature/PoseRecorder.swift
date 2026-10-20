import Foundation
import RepEngine

/// Debug-only pose recorder (roadmap P3-04, doc 05 §8): keeps the raw `PoseFrame`s of a session and exports them in
/// the shared vector format (plain JSON). `tools/pose-recorder/import.py` validates, gzips and adds them to
/// shared/test-vectors/pushup. Only landmarks — never video (CLAUDE.md §4.3).
public final class PoseRecorder {
    public struct Label: Sendable {
        public var humanCount: Int
        public var placement: String   // side | front
        public var camera: String      // front | rear
        public var tags: [String]
        public var notes: String
        public var labeller: String

        public init(humanCount: Int, placement: String = "side", camera: String = "front", tags: [String] = [],
                    notes: String = "", labeller: String = "") {
            self.humanCount = humanCount
            self.placement = placement
            self.camera = camera
            self.tags = tags
            self.notes = notes
            self.labeller = labeller
        }
    }

    private var frames: [[String: Any]] = []
    private var size: CGSize = .zero
    private var startMs: Int64?

    public init() {}

    public var frameCount: Int { frames.count }

    func append(_ f: PoseFrame, imageSize: CGSize) {
        guard frames.count < 30 * 60 * 5 else { return } // 5 min cap
        size = imageSize
        let t0 = startMs ?? f.tMs
        startMs = t0
        var frame: [String: Any] = [
            "t": f.tMs - t0,
            "lm": f.landmarks.map { [r($0.x), r($0.y), r($0.z), r($0.visibility), r($0.presence)] },
            "w": f.world.map { [r($0.x), r($0.y), r($0.z)] },
        ]
        if let m = f.motion { frame["motion"] = r(m) }
        frames.append(frame)
    }

    private func r(_ v: Double) -> Double { (v * 100_000).rounded() / 100_000 }

    /// Writes the vector JSON to a temporary file and returns its URL (for the share sheet).
    public func export(label: Label, device: String) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let id = "real-\(label.placement)-\(label.humanCount)-\(stamp)"
        let tags = label.tags
        let vector: [String: Any] = [
            "id": id,
            "specVersion": RepEngineInfo.specVersion,
            "meta": [
                "placement": label.placement, "camera": label.camera, "device": device, "fps": 30,
                "imageWidth": Int(size.width), "imageHeight": Int(size.height), "tags": tags,
                "humanCount": label.humanCount, "labeller": label.labeller, "notes": label.notes,
            ],
            "frames": frames,
            "expected": ["counted": tags.contains("cheat") ? 0 : label.humanCount, "toleranceCounted": tags.contains("edge") ? 1 : 0],
        ]
        let data = try JSONSerialization.data(withJSONObject: vector, options: [.sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).json")
        try data.write(to: url)
        return url
    }
}
