import Foundation

/// What to tell the user before the first rep (doc 05 §6 placement guide). Same rules on Android.
public enum Guidance: String, Sendable {
    case stepIntoFrame, turnPhoneToSide, showWholeBody, moveBack, comeCloser, turnOnLight, getIntoPlank, ready

    /// - `personVisible`: MediaPipe currently finds a person; `tooDark`: low-light flag from the camera.
    public static func current(state: RepState, features: RepFeatures?, personVisible: Bool, tooDark: Bool) -> Guidance {
        if tooDark { return .turnOnLight }
        guard state == .notReady else { return .ready }
        guard personVisible, let f = features else { return .stepIntoFrame }
        if f.visibility < PushupSpecV2.Visibility.requiredLandmarkMin { return .showWholeBody }
        // Front placement (spec v2) frames only the upper body: no whole-body size check.
        if f.mode != .front {
            if f.bbox > PushupSpecV2.Plank.bboxHeightMax { return .moveBack }
            if f.bbox < PushupSpecV2.Plank.bboxHeightMin { return .comeCloser }
        }
        if f.placement == .unknown { return .turnPhoneToSide }
        return .getIntoPlank
    }
}

/// Rate limits form hints (doc 05 §5): at most one every `minIntervalMs`; the same reason at most `maxSameInARow`
/// times in a row — after that the UI shows the illustrated tip instead (`showTip`).
public struct HintGate: Sendable {
    public struct Hint: Sendable, Equatable {
        public let reason: RejectReason
        public let showTip: Bool
    }

    private var lastAt: Int64?
    private var lastReason: RejectReason?
    private var sameInARow = 0

    public init() {}

    public mutating func offer(_ reason: RejectReason, at t: Int64) -> Hint? {
        if let lastAt, t - lastAt < Int64(PushupSpecV2.Hints.minIntervalMs) { return nil }
        sameInARow = reason == lastReason ? sameInARow + 1 : 1
        lastReason = reason
        lastAt = t
        return Hint(reason: reason, showTip: sameInARow > PushupSpecV2.Hints.maxSameInARow)
    }
}
