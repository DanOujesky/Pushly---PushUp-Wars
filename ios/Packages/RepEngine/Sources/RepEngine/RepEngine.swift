import Foundation

/// RepEngine namespace info. Constants come only from `Generated/PushupSpecV1.swift` (shared/rep-engine-spec).
public enum RepEngineInfo {
    public static let specVersion = PushupSpecV1.specVersion
}

// MARK: - Input

/// One normalised image landmark (MediaPipe): un-mirrored, upright image, y down.
public struct PoseLandmark: Sendable, Equatable {
    public var x, y, z, visibility, presence: Double

    public init(x: Double, y: Double, z: Double, visibility: Double, presence: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility
        self.presence = presence
    }
}

/// One world landmark in metres (hip-centred, y down).
public struct WorldPoint: Sendable, Equatable {
    public var x, y, z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// One analysed camera frame (doc 05 §3): 33 landmarks + 33 world landmarks.
public struct PoseFrame: Sendable, Equatable {
    public var tMs: Int64
    public var landmarks: [PoseLandmark]
    public var world: [WorldPoint]
    /// Device motion RMS in g over the frame interval (anti-cheat, doc 06 §2.1); nil = not measured.
    public var motion: Double?

    public init(tMs: Int64, landmarks: [PoseLandmark], world: [WorldPoint], motion: Double? = nil) {
        self.tMs = tMs
        self.landmarks = landmarks
        self.world = world
        self.motion = motion
    }
}

// MARK: - Output

public enum RepState: String, Sendable {
    case notReady, top, descending, bottom, ascending, recover
}

public enum Placement: String, Sendable {
    case side, front, unknown
}

/// Why a rep did not count (doc 05 §5). Raw values are the wire codes used in rep logs and test vectors.
public enum RejectReason: String, Sendable, CaseIterable {
    case notDeepEnough = "NOT_DEEP_ENOUGH"
    case noLockout = "NO_LOCKOUT"
    case hipsSagging = "HIPS_SAGGING"
    case hipsPiked = "HIPS_PIKED"
    case kneesDown = "KNEES_DOWN"
    case bodyNotVisible = "BODY_NOT_VISIBLE"
    case tooFast = "TOO_FAST"
    case tooSlow = "TOO_SLOW"
    case irregularMotion = "IRREGULAR_MOTION"
    case integrity = "INTEGRITY"
}

public struct CountedRep: Sendable, Equatable {
    public let index: Int
    public let quality: Int
    public let tStart: Int64
    public let tBottom: Int64
    public let tEnd: Int64
    public let minElbow: Double
    public let maxElbow: Double
    public let minBodyLine: Double
    public let depth: Double
}

public enum RepEvent: Sendable, Equatable {
    case counted(CountedRep)
    case rejected(RejectReason, t: Int64)
}

/// Per-frame features (doc 05 §4). Exposed for the UI (guidance) and the rep log trace.
public struct RepFeatures: Sendable, Equatable {
    public let t: Int64
    public let leftSide: Bool
    public let visibility: Double
    public let elbow: Double
    public let bodyLine: Double
    public let knee: Double
    /// Pixels; > 0 = hip below the shoulder–ankle line (sagging).
    public let hipDeviation: Double
    public let torsoTilt: Double
    public let bbox: Double
    public let shoulderY: Double
    public let upperArm: Double
    public let placement: Placement
    public let motion: Double?
}

// MARK: - Math

enum RepMath {
    static func angle(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double {
        var ba = [Double](), bc = [Double]()
        for i in 0..<a.count {
            ba.append(a[i] - b[i])
            bc.append(c[i] - b[i])
        }
        let na = sqrt(ba.reduce(0) { $0 + $1 * $1 })
        let nc = sqrt(bc.reduce(0) { $0 + $1 * $1 })
        if na < 1e-9 || nc < 1e-9 { return 180.0 }
        var dot = 0.0
        for i in 0..<ba.count { dot += ba[i] * bc[i] }
        let cosine = max(-1.0, min(1.0, dot / (na * nc)))
        return acos(cosine) * 180.0 / Double.pi
    }

    static func dist(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0
        for i in 0..<a.count { s += (a[i] - b[i]) * (a[i] - b[i]) }
        return sqrt(s)
    }

    static func clamp01(_ v: Double) -> Double { max(0.0, min(1.0, v)) }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        if n == 0 { return 0.0 }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Direction changes of a sequence, ignoring wiggles smaller than `threshold` (zig-zag filter).
    static func reversals(_ values: [Double], threshold: Double) -> Int {
        guard var ref = values.first else { return 0 }
        var direction = 0
        var count = 0
        for v in values.dropFirst() {
            if direction == 0 {
                if v - ref >= threshold {
                    direction = 1
                    ref = v
                } else if ref - v >= threshold {
                    direction = -1
                    ref = v
                }
            } else if direction == 1 {
                if v > ref {
                    ref = v
                } else if ref - v >= threshold {
                    count += 1
                    direction = -1
                    ref = v
                }
            } else {
                if v < ref {
                    ref = v
                } else if v - ref >= threshold {
                    count += 1
                    direction = 1
                    ref = v
                }
            }
        }
        return count
    }
}

/// One-Euro filter for one scalar (Casiez et al.); dt in seconds.
struct OneEuroFilter {
    let minCutoff: Double
    let beta: Double
    let dCutoff: Double
    private var x: Double?
    private var dx = 0.0

    init(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    mutating func callAsFunction(_ value: Double, dt: Double) -> Double {
        guard let prev = x else {
            x = value
            return value
        }
        let d = (value - prev) / dt
        dx = dx + Self.alpha(dCutoff, dt) * (d - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let next = prev + Self.alpha(cutoff, dt) * (value - prev)
        x = next
        return next
    }
}

// MARK: - Engine

/// Push-up counter (doc 05 §4–5). Pure and deterministic: same input → same events as Android and
/// tools/reference/pushly_ref/rep_engine.py (verified by shared/test-vectors/pushup).
public final class RepEngine {
    private typealias S = PushupSpecV1
    private static let sides: [Bool: (Int, Int, Int, Int, Int, Int)] = [
        true: (11, 13, 15, 23, 25, 27),
        false: (12, 14, 16, 24, 26, 28),
    ]

    public let imageWidth: Double
    public let imageHeight: Double

    public private(set) var state: RepState = .notReady
    public private(set) var counted = 0
    public private(set) var lastFeatures: RepFeatures?

    private var filters: [Int: OneEuroFilter] = [:]
    private var leftSide: Bool?
    private var switchFrames = 0
    private var lastT: Int64?
    private var counts: [String: Int] = [:]
    private var lowVisSince: Int64?
    private var offPlankSince: Int64?
    private var topShoulderY = 0.0
    private var armSamples: [Double] = []
    private var armRef = 0.0
    private var rep: [RepFeatures] = []
    private var repStart: Int64 = 0
    private var tBottom: Int64 = 0
    private var ascStart: Int64 = 0
    private var pendingFirst: RepFeatures?

    public init(imageWidth: Double, imageHeight: Double) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    // MARK: Features

    private func smooth(_ key: Int, _ value: Double, dt: Double) -> Double {
        var f = filters[key] ?? OneEuroFilter(minCutoff: S.Smoothing.OneEuro.minCutoff, beta: S.Smoothing.OneEuro.beta,
                                              dCutoff: S.Smoothing.OneEuro.dCutoff)
        let out = f(value, dt: dt)
        filters[key] = f
        return out
    }

    func features(_ frame: PoseFrame) -> RepFeatures {
        let t = frame.tMs
        let dt: Double
        if let last = lastT, t > last { dt = Double(t - last) / 1000.0 } else { dt = 1.0 / 30.0 }
        lastT = t
        let lm = frame.landmarks, w = frame.world
        var img: [[Double]] = []
        var world: [[Double]] = []
        img.reserveCapacity(33)
        world.reserveCapacity(33)
        for i in 0..<33 {
            let x = smooth(i * 5, lm[i].x, dt: dt) * imageWidth
            let y = smooth(i * 5 + 1, lm[i].y, dt: dt) * imageHeight
            img.append([x, y])
            world.append([smooth(i * 5 + 2, w[i].x, dt: dt), smooth(i * 5 + 3, w[i].y, dt: dt), smooth(i * 5 + 4, w[i].z, dt: dt)])
        }
        let vis = lm.map(\.visibility)
        let req = S.Visibility.requiredLandmarkMin

        func sideVis(_ left: Bool) -> Double {
            guard let s = Self.sides[left] else { return 0 }
            return min(vis[s.0], vis[s.1], vis[s.2], vis[s.3], max(vis[s.4], vis[s.5]))
        }
        let vl = sideVis(true), vr = sideVis(false)
        if let current = leftSide {
            let (cur, other) = current ? (vl, vr) : (vr, vl)
            if other - cur > S.Stability.sideSwitchVisibilityDelta {
                switchFrames += 1
                if switchFrames >= S.Stability.sideSwitchFrames {
                    leftSide = !current
                    switchFrames = 0
                }
            } else {
                switchFrames = 0
            }
        } else {
            leftSide = vl >= vr
        }
        let left = leftSide ?? true
        let sv = left ? vl : vr
        let (sh, el, wr, hip, kn, an) = Self.sides[left] ?? (11, 13, 15, 23, 25, 27)
        let ankleOK = vis[an] >= req
        let end = ankleOK ? an : kn

        let elbow = RepMath.angle(world[sh], world[el], world[wr])
        let bodyLine = RepMath.angle(world[sh], world[hip], world[end])
        let knee = ankleOK ? RepMath.angle(world[hip], world[kn], world[an]) : 180.0

        let a = img[sh], b = img[end], h = img[hip]
        let yLine = abs(b[0] - a[0]) > 1e-6 ? a[1] + (b[1] - a[1]) * (h[0] - a[0]) / (b[0] - a[0]) : h[1]
        let hipDev = h[1] - yLine
        let torsoTilt = atan2(abs(b[1] - a[1]), abs(b[0] - a[0])) * 180.0 / Double.pi

        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        var any = false
        for i in 0..<33 where vis[i] >= S.Framing.bboxVisibilityMin {
            any = true
            minX = min(minX, lm[i].x)
            maxX = max(maxX, lm[i].x)
            minY = min(minY, lm[i].y)
            maxY = max(maxY, lm[i].y)
        }
        let bbox = any ? max(maxX - minX, maxY - minY) : 0.0

        let shMid = [(img[11][0] + img[12][0]) / 2, (img[11][1] + img[12][1]) / 2]
        let hipMid = [(img[23][0] + img[24][0]) / 2, (img[23][1] + img[24][1]) / 2]
        let torsoLen = RepMath.dist(shMid, hipMid)
        let ratio = torsoLen > 1e-6 ? RepMath.dist(img[11], img[12]) / torsoLen : 99.0
        let placement: Placement = ratio < S.Framing.placementSideMaxRatio ? .side
            : ratio > S.Framing.placementFrontMinRatio ? .front : .unknown

        return RepFeatures(t: t, leftSide: left, visibility: sv, elbow: elbow, bodyLine: bodyLine, knee: knee,
                           hipDeviation: hipDev, torsoTilt: torsoTilt, bbox: bbox, shoulderY: img[sh][1],
                           upperArm: RepMath.dist(img[sh], img[el]), placement: placement, motion: frame.motion)
    }

    // MARK: Helpers

    private func stable(_ name: String, _ cond: Bool) -> Bool {
        guard cond else {
            counts[name] = 0
            return false
        }
        let n = (counts[name] ?? 0) + 1
        if n >= S.Stability.stableFrames {
            counts[name] = 0
            return true
        }
        counts[name] = n
        return false
    }

    private func enter(_ s: RepState) {
        state = s
        counts = [:]
    }

    private func bottomMax(_ f: RepFeatures) -> Double {
        f.placement == .front ? S.Elbow.frontBottomMaxDeg : S.Elbow.bottomMaxDeg
    }

    private func depth(_ f: RepFeatures) -> Double {
        armRef > 1e-6 ? (f.shoulderY - topShoulderY) / armRef : 0.0
    }

    private func updateTop(_ f: RepFeatures) {
        topShoulderY = f.shoulderY
        armSamples.append(f.upperArm)
        if armSamples.count > 30 { armSamples.removeFirst() }
        armRef = RepMath.median(armSamples)
    }

    // MARK: Step

    /// Feeds one frame; returns the events it produced (usually none).
    public func process(_ frame: PoseFrame) -> [RepEvent] {
        var events: [RepEvent] = []
        let f = features(frame)
        lastFeatures = f
        let topMin = S.Elbow.topMinDeg

        let lostMs = Int64(S.Stability.trackingLostMs)
        if f.visibility < S.Visibility.lostBelow {
            if lowVisSince == nil { lowVisSince = f.t }
        } else {
            lowVisSince = nil
        }
        if f.torsoTilt > S.Plank.torsoTiltMaxDeg {
            if offPlankSince == nil { offPlankSince = f.t }
        } else {
            offPlankSince = nil
        }
        let visLost = lowVisSince.map { f.t - $0 >= lostMs } ?? false
        let plankLost = offPlankSince.map { f.t - $0 >= lostMs } ?? false
        if state != .notReady && (visLost || plankLost) {
            if [.descending, .bottom, .ascending].contains(state) && visLost {
                events.append(.rejected(.bodyNotVisible, t: f.t))
            }
            rep = []
            enter(.notReady)
            return events
        }

        switch state {
        case .notReady:
            let plank = f.torsoTilt <= S.Plank.torsoTiltMaxDeg && f.bodyLine >= S.Plank.bodyLineMinDeg
                && f.elbow >= topMin && f.visibility >= S.Visibility.requiredLandmarkMin
                && S.Plank.bboxHeightMin <= f.bbox && f.bbox <= S.Plank.bboxHeightMax && f.placement != .unknown
            if stable("plank", plank) {
                armSamples = []
                updateTop(f)
                enter(.top)
            }
        case .top:
            let cond = f.elbow < topMin - S.Elbow.hysteresisDeg
            if cond && (counts["down"] ?? 0) == 0 { pendingFirst = f }
            if stable("down", cond) {
                let first = pendingFirst ?? f
                rep = first == f ? [] : [first]
                rep.append(f)
                repStart = first.t
                enter(.descending)
            } else if !cond {
                updateTop(f)
            }
        case .descending:
            rep.append(f)
            if stable("bottom", f.elbow <= bottomMax(f) && depth(f) >= S.Depth.minDepthRatio) {
                tBottom = f.t
                enter(.bottom)
            } else if stable("upNoBottom", f.elbow >= topMin) {
                events.append(.rejected(.notDeepEnough, t: f.t))
                rep = []
                updateTop(f)
                enter(.top)
            }
        case .bottom:
            rep.append(f)
            if stable("up", f.elbow > bottomMax(f) + S.Elbow.hysteresisDeg) {
                ascStart = f.t
                enter(.ascending)
            }
        case .ascending:
            rep.append(f)
            if stable("lockout", f.elbow >= topMin) {
                if let e = evaluate(tEnd: f.t) { events.append(e) }
                rep = []
                updateTop(f)
                enter(.top)
            } else if f.t - ascStart > Int64(S.Elbow.lockoutWaitMs) || stable("downAgain", f.elbow <= bottomMax(f)) {
                events.append(.rejected(.noLockout, t: f.t))
                rep = []
                enter(.recover)
            }
        case .recover:
            if stable("recovered", f.elbow >= topMin) {
                updateTop(f)
                enter(.top)
            }
        }
        return events
    }

    // MARK: Evaluation (doc 05 §5)

    private func evaluate(tEnd: Int64) -> RepEvent? {
        let frames = rep
        let n = Double(frames.count)
        guard !frames.isEmpty else { return nil }
        let req = S.Visibility.requiredLandmarkMin
        if Double(frames.filter { $0.visibility >= req }.count) / n < S.Visibility.requiredFrameShare {
            return .rejected(.bodyNotVisible, t: tEnd)
        }
        if Double(frames.filter { $0.knee >= S.Form.kneeMinDeg }.count) / n < S.Form.kneeFrameShare {
            return .rejected(.kneesDown, t: tEnd)
        }
        let bad = frames.filter { $0.bodyLine < S.Form.bodyLineMinDeg }
        if (n - Double(bad.count)) / n < S.Form.bodyLineFrameShare {
            let meanDev = bad.reduce(0.0) { $0 + $1.hipDeviation } / Double(bad.count)
            return .rejected(meanDev > 0 ? .hipsSagging : .hipsPiked, t: tEnd)
        }
        let duration = tEnd - repStart
        if duration < Int64(S.Tempo.minRepMs) { return .rejected(.tooFast, t: tEnd) }
        if duration > Int64(S.Tempo.maxRepMs) { return .rejected(.tooSlow, t: tEnd) }
        if RepMath.reversals(frames.map(\.elbow), threshold: S.Form.maxDirectionReversalsDeg) > 1 {
            return .rejected(.irregularMotion, t: tEnd)
        }
        let motions = frames.compactMap(\.motion)
        if !motions.isEmpty {
            let shaky = Double(motions.filter { $0 > S.Integrity.deviceMotionMaxRms }.count) / Double(motions.count)
            if shaky > S.Integrity.deviceMotionFrameShare { return .rejected(.integrity, t: tEnd) }
        }

        let maxDepth = frames.map(depth).max() ?? 0
        let maxElbow = frames.map(\.elbow).max() ?? 0
        let minElbow = frames.map(\.elbow).min() ?? 0
        let minLine = frames.map(\.bodyLine).min() ?? 0
        let meanLine = frames.reduce(0.0) { $0 + $1.bodyLine } / n
        let depthS = RepMath.clamp01((maxDepth - S.Depth.minDepthRatio) / 0.40)
        let lockS = RepMath.clamp01((maxElbow - S.Elbow.topMinDeg) / 20.0)
        let lineS = RepMath.clamp01((meanLine - S.Form.bodyLineMinDeg) / 25.0)
        let d = Double(duration)
        let tempoS: Double = if duration < 1000 {
            RepMath.clamp01((d - Double(S.Tempo.minRepMs)) / 550.0)
        } else if duration <= 3000 {
            1.0
        } else {
            RepMath.clamp01(1.0 - (d - 3000) / 5000.0)
        }
        let w = S.Quality.Weights.self
        let q = w.depth * depthS + w.lockout * lockS + w.bodyLine * lineS + w.tempo * tempoS
        counted += 1
        return .counted(CountedRep(index: counted, quality: Int(floor(100 * q + 0.5)), tStart: repStart, tBottom: tBottom,
                                   tEnd: tEnd, minElbow: minElbow, maxElbow: maxElbow, minBodyLine: minLine, depth: maxDepth))
    }
}
