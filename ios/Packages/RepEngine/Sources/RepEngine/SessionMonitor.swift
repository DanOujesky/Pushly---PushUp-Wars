import Compression
import Foundation

/// On-device session integrity signals (doc 06 §2.3–2.4) and the 10 Hz feature trace for the rep log.
/// Port of tools/reference/pushly_ref/integrity.py; shared vectors shared/test-vectors/integrity (same as Android).
/// Feed every frame after `RepEngine.process` with its time since the session start.
public struct SessionMonitor: Sendable {
    public static let traceIntervalMs: Int64 = 100
    static let gapMs: Int64 = 400
    static let gapsPerMinuteOK = 3.0
    static let frozenFrames = 5
    static let limbSpreadOK = 0.15
    static let limbSpreadRange = 0.35
    static let limbMinSamples = 30
    static let sides: [Bool: [Int]] = [true: [11, 13, 15, 23, 25, 27], false: [12, 14, 16, 24, 26, 28]]

    public private(set) var rows: [[Int64]] = []
    public private(set) var gaps = 0
    public private(set) var frozen = 0
    private var lastSample: Int64?
    private var lastFrameT: Int64?
    private var firstT: Int64?
    private var prevXY: [Double]?
    private var same = 0
    private var limbs: [String: [Double]] = ["upperArm": [], "forearm": [], "thigh": [], "shin": []]

    public init() {}

    static func rnd(_ x: Double) -> Int64 { Int64((x + 0.5).rounded(.down)) }

    static func score(_ x: Double) -> Double { ((min(1, max(0, x)) * 1000 + 0.5).rounded(.down)) / 1000 }

    public mutating func frame(_ frame: PoseFrame, features: RepFeatures?, relativeMs: Int64) {
        let t = frame.tMs
        if firstT == nil { firstT = t }
        if let last = lastFrameT, t - last > Self.gapMs { gaps += 1 }
        lastFrameT = t
        let xy = frame.landmarks.flatMap { [$0.x, $0.y] }
        if let prev = prevXY, prev == xy {
            same += 1
            if same == Self.frozenFrames - 1 { frozen += 1 }
        } else {
            same = 0
        }
        prevXY = xy
        guard let f = features, let idx = Self.sides[f.leftSide], frame.landmarks.count == 33, frame.world.count == 33 else {
            return
        }
        let (sh, el, wr, hip, kn, an) = (idx[0], idx[1], idx[2], idx[3], idx[4], idx[5])
        let req = PushupSpecV2.Visibility.requiredLandmarkMin
        let pairs: [(String, Int, Int)] = [("upperArm", sh, el), ("forearm", el, wr), ("thigh", hip, kn), ("shin", kn, an)]
        for (name, a, b) in pairs where frame.landmarks[a].visibility >= req && frame.landmarks[b].visibility >= req {
            let p = frame.world[a], q = frame.world[b]
            limbs[name, default: []].append(((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y) + (p.z - q.z) * (p.z - q.z))
                .squareRoot())
        }
        if lastSample == nil || relativeMs - (lastSample ?? 0) >= Self.traceIntervalMs {
            lastSample = relativeMs
            rows.append([relativeMs, Self.rnd(f.elbow), Self.rnd(f.bodyLine), Self.rnd(f.visibility * 100),
                         f.motion.map { Self.rnd($0 * 1000) } ?? -1])
        }
    }

    /// 0–1: camera feed gaps (> 400 ms) above 3 per minute, or a frozen feed → 1.
    public var continuity: Double {
        if frozen > 0 { return 1 }
        let span = Double((lastFrameT ?? 0) - (firstT ?? 0))
        let rate = Double(gaps) / max(span / 60_000, 1)
        return Self.score((rate - Self.gapsPerMinuteOK) / Self.gapsPerMinuteOK)
    }

    /// 0–1: how much the world-landmark limb lengths wobble (flat replay on a screen).
    public var replay: Double {
        var worst = 0.0
        for values in limbs.values where values.count >= Self.limbMinSamples {
            let v = values.sorted()
            let n = v.count
            let p10 = v[Int(0.1 * Double(n - 1))], p50 = v[Int(0.5 * Double(n - 1))], p90 = v[Int(0.9 * Double(n - 1))]
            if p50 > 1e-6 { worst = max(worst, (p90 - p10) / p50) }
        }
        return Self.score((worst - Self.limbSpreadOK) / Self.limbSpreadRange)
    }

    /// The trace for the rep log: JSON, raw deflate, base64 (decoded by the server, doc 06 §4).
    public var encodedTrace: String? {
        let body = rows.map { "[" + $0.map(String.init).joined(separator: ",") + "]" }.joined(separator: ",")
        let json = "{\"v\":1,\"fields\":[\"t\",\"elbow\",\"bodyLine\",\"vis\",\"motion\"],\"rows\":[\(body)]}"
        let input = Data(json.utf8)
        let capacity = input.count + 1024
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(d, capacity, s, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return out.prefix(written).base64EncodedString()
    }
}
