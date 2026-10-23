package app.pushly.engine.rep

import app.pushly.engine.rep.generated.PushupSpecV2

/** What to tell the user before the first rep (doc 05 §6 placement guide). Same rules as iOS `Guidance`. */
enum class Guidance {
    StepIntoFrame, TurnPhoneToSide, ShowWholeBody, MoveBack, ComeCloser, TurnOnLight, GetIntoPlank, Ready;

    companion object {
        /** [allowFront] = false in battles: a FRONT placement must turn to the side (D-064). */
        fun current(state: RepState, features: RepFeatures?, personVisible: Boolean, tooDark: Boolean, allowFront: Boolean = true): Guidance {
            if (tooDark) return TurnOnLight
            if (state != RepState.NotReady) return Ready
            if (!personVisible || features == null) return StepIntoFrame
            if (features.visibility < PushupSpecV2.Visibility.REQUIRED_LANDMARK_MIN) return ShowWholeBody
            // Front placement (spec v2) frames only the upper body: no whole-body size check.
            if (features.mode != Placement.Front) {
                if (features.bbox > PushupSpecV2.Plank.BBOX_HEIGHT_MAX) return MoveBack
                if (features.bbox < PushupSpecV2.Plank.BBOX_HEIGHT_MIN) return ComeCloser
            }
            if (features.placement == Placement.Unknown || (!allowFront && features.placement == Placement.Front)) return TurnPhoneToSide
            return GetIntoPlank
        }
    }
}

/**
 * Rate limits form hints (doc 05 §5): at most one every minIntervalMs; the same reason at most maxSameInARow times
 * in a row — after that the UI shows the illustrated tip instead ([Hint.showTip]). Same as iOS `HintGate`.
 */
class HintGate {
    data class Hint(val reason: RejectReason, val showTip: Boolean)

    private var lastAt: Long? = null
    private var lastReason: RejectReason? = null
    private var sameInARow = 0

    fun offer(reason: RejectReason, t: Long): Hint? {
        lastAt?.let { if (t - it < PushupSpecV2.Hints.MIN_INTERVAL_MS) return null }
        sameInARow = if (reason == lastReason) sameInARow + 1 else 1
        lastReason = reason
        lastAt = t
        return Hint(reason, sameInARow > PushupSpecV2.Hints.MAX_SAME_IN_A_ROW)
    }
}
