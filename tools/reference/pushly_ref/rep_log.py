"""Server plausibility checks for an uploaded rep log (doc 06 §4) + conversion to server time.

The Edge Function `submit-rep-session` (supabase/functions/_shared/replog.ts) implements exactly this and runs the
shared vectors (shared/test-vectors/rep-log). Checks needing history (volume ceilings, personal-best jumps) and the
wake decision run in SQL (app.apply_validated_session). Signature / attestation checks come with P4-02.

Result codes
- hard (session stored, verified = false, hard flag): spec_version_unsupported, reps_not_sequential, rep_duration,
  rate_sustained, reps_outside_session, clock_in_future, sets_invalid
  trace_mismatch (the feature trace doesn't show the claimed reps — forged log, integrity.trace_codes)
- hold (verified = false until reviewed, soft flag): long_set, feed_discontinuity (camera feed gaps / frozen)
- soft (flag only): fast_reps, suspicion_replay, suspicion_motion, trace_missing
"""
from __future__ import annotations

from datetime import datetime

from .integrity import trace_codes

SUPPORTED_SPEC_VERSIONS = {1}
MIN_REP_MS, MAX_REP_MS = 450, 8000
FAST_REP_MS, FAST_RUN = 600, 3                  # ≥ 3 consecutive reps < 600 ms → soft
SUSTAINED_REPS, SUSTAINED_RATE = 20, 1.6        # > 1.6 reps/s over 20 rep intervals → hard
SET_GAP_MS, LONG_SET_REPS = 5000, 150           # continuous set = gaps ≤ 5 s; > 150 reps → hold
FUTURE_TOLERANCE_MS = 120_000
SESSION_SLACK_MS = 1000
REPLAY_MAX, MOTION_MAX = 0.6, 0.5


def iso_ms(s: str) -> int:
    return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000)


def session_start_ms(log: dict) -> tuple[int, bool]:
    """Server-time epoch ms of the session start, and whether a server anchor was used."""
    t = log["timing"]
    anchor = t.get("serverAnchor")
    if anchor:
        return iso_ms(anchor["serverTime"]) + (t["monotonicStartMs"] - anchor["monotonicAtAnchorMs"]), True
    return iso_ms(t["wallStart"]), False


def check(log: dict, received_ms: int) -> dict:
    """Returns {hard: [...], hold: [...], soft: [...], anchored, session} — session in server time for SQL."""
    hard, hold, soft = [], [], []
    t = log["timing"]
    duration = t["monotonicEndMs"] - t["monotonicStartMs"]
    reps = log["reps"]

    if log["specVersion"] not in SUPPORTED_SPEC_VERSIONS:
        hard.append("spec_version_unsupported")
    seq_ok = duration >= 0
    for k, r in enumerate(reps):
        if r["i"] != k + 1 or not (r["tStartMs"] <= r["tBottomMs"] <= r["tEndMs"]):
            seq_ok = False
        if k and r["tStartMs"] < reps[k - 1]["tEndMs"]:
            seq_ok = False
    if not seq_ok:
        hard.append("reps_not_sequential")
    if any(not (MIN_REP_MS <= r["tEndMs"] - r["tStartMs"] <= MAX_REP_MS) for r in reps):
        hard.append("rep_duration")
    ends = [r["tEndMs"] for r in reps]
    if any(ends[j + SUSTAINED_REPS] - ends[j] < SUSTAINED_REPS / SUSTAINED_RATE * 1000
           for j in range(len(ends) - SUSTAINED_REPS)):
        hard.append("rate_sustained")
    if reps and (reps[0]["tStartMs"] < 0 or reps[-1]["tEndMs"] > duration + SESSION_SLACK_MS):
        hard.append("reps_outside_session")
    sets = log.get("sets") or []
    if any(s["endMs"] < s["startMs"] or s["endMs"] > duration + SESSION_SLACK_MS for s in sets):
        hard.append("sets_invalid")

    start, anchored = session_start_ms(log)
    ended = start + max(duration, 0)
    if ended > received_ms + FUTURE_TOLERANCE_MS:
        hard.append("clock_in_future")

    run = 0
    for r in reps:
        run = run + 1 if r["tEndMs"] - r["tStartMs"] < FAST_REP_MS else 0
        if run >= FAST_RUN:
            soft.append("fast_reps")
            break
    best_set = cur = 0
    for k, r in enumerate(reps):
        cur = cur + 1 if k and r["tStartMs"] - reps[k - 1]["tEndMs"] <= SET_GAP_MS else 1
        best_set = max(best_set, cur)
    if best_set > LONG_SET_REPS:
        hold.append("long_set")
    sus = log.get("suspicion") or {}
    if sus.get("continuity", 0) >= 1:
        hold.append("feed_discontinuity")
    if sus.get("replay", 0) > REPLAY_MAX:
        soft.append("suspicion_replay")
    if sus.get("motion", 0) > MOTION_MAX:
        soft.append("suspicion_motion")

    trace_hard, trace_soft = trace_codes(log)
    hard += trace_hard
    soft += trace_soft

    ring = t.get("ringStartedAtMonotonicMs")
    ctx = log["context"]
    session = {
        "sessionId": log["sessionId"],
        "context": ctx["type"],
        "occurrenceId": ctx.get("occurrenceId"),
        "startedAt": start,
        "endedAt": ended,
        "ringAt": start + (ring - t["monotonicStartMs"]) if ring is not None else None,
        "outcome": log["outcome"],
        "snoozes": log.get("snoozes", 0),
        "reps": [{"tStart": start + r["tStartMs"], "tEnd": start + r["tEndMs"], "quality": r["quality"]} for r in reps],
        "sets": [{"start": start + s["startMs"], "end": start + s["endMs"]} for s in sets],
        "sprintStart": start + log["sprintStartMs"] if log.get("sprintStartMs") is not None else None,
        "rejected": log["rejected"],
        "specVersion": log["specVersion"],
        "appVersion": log["appVersion"],
        "platform": log["platform"],
        "bestSet": best_set,
    }
    return {"hard": hard, "hold": hold, "soft": soft, "anchored": anchored, "session": session}
