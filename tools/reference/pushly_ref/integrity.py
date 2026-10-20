"""On-device session integrity signals (doc 06 §2 items 3–4) + the server's feature-trace check (doc 06 §4).

Executable spec for: `SessionMonitor` (iOS WakeFlowFeature / Android :feature:wakeflow, vectors
shared/test-vectors/integrity) and `trace_codes` (Edge Function submit-rep-session, vectors shared/test-vectors/rep-log).

- Feature trace: the session at 10 Hz — [t (ms since session start), elbow°, bodyLine°, visibility×100, motion×1000
  or −1] — JSON, raw-deflated, base64 in the rep log (`featureTrace`). Never video (CLAUDE.md §4.3).
- continuity (0–1): camera feed gaps > 400 ms above 3 per minute, or a frozen feed (≥ 5 identical frames) → 1.
- replay (0–1): spread of world-landmark limb lengths over the session; a flat replay on a screen makes them wobble
  (doc 06 §2.4c). Soft signal only — the server weighs it, the client never blocks on it.
Rounding is floor(x + 0.5) everywhere (no banker's rounding) so all implementations agree.
"""
from __future__ import annotations

import base64
import json
import math
import zlib

from .rep_engine import SIDES, SPEC

TRACE_INTERVAL_MS = 100
GAP_MS = 400
GAPS_PER_MINUTE_OK = 3.0
FROZEN_FRAMES = 5
LIMB_SPREAD_OK = 0.15
LIMB_SPREAD_RANGE = 0.35
LIMB_MIN_SAMPLES = 30
TRACE_FIELDS = ["t", "elbow", "bodyLine", "vis", "motion"]


def rnd(x: float) -> int:
    return int(math.floor(x + 0.5))


def score(x: float) -> float:
    return math.floor(min(1.0, max(0.0, x)) * 1000 + 0.5) / 1000


def dist3(a, b) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


class SessionMonitor:
    """Feed every frame (after RepEngine.process) with its session-relative time."""

    def __init__(self) -> None:
        self.rows: list[list[int]] = []
        self._last_sample: int | None = None
        self._last_frame_t: int | None = None
        self._first_t: int | None = None
        self.gaps = 0
        self._prev_xy: list | None = None
        self._same = 0
        self.frozen = 0
        self.limbs: dict[str, list[float]] = {"upperArm": [], "forearm": [], "thigh": [], "shin": []}

    def frame(self, frame: dict, features, rel_t: int) -> None:
        t = int(frame["t"])
        if self._first_t is None:
            self._first_t = t
        if self._last_frame_t is not None and t - self._last_frame_t > GAP_MS:
            self.gaps += 1
        self._last_frame_t = t
        xy = [(p[0], p[1]) for p in frame["lm"]]
        if self._prev_xy is not None and xy == self._prev_xy:
            self._same += 1
            if self._same == FROZEN_FRAMES - 1:
                self.frozen += 1
        else:
            self._same = 0
        self._prev_xy = xy
        if features is None:
            return
        sh, el, wr, hip, kn, an = SIDES[features.side]
        lm, w = frame["lm"], frame["w"]
        req = SPEC["visibility"]["requiredLandmarkMin"]
        for name, (a, b) in {"upperArm": (sh, el), "forearm": (el, wr), "thigh": (hip, kn), "shin": (kn, an)}.items():
            if lm[a][3] >= req and lm[b][3] >= req:
                self.limbs[name].append(dist3(w[a], w[b]))
        if self._last_sample is None or rel_t - self._last_sample >= TRACE_INTERVAL_MS:
            self._last_sample = rel_t
            motion = features.motion
            self.rows.append([rel_t, rnd(features.elbow), rnd(features.body_line), rnd(features.vis * 100),
                              rnd(motion * 1000) if motion is not None else -1])

    def continuity(self) -> float:
        if self.frozen:
            return 1.0
        span = (self._last_frame_t or 0) - (self._first_t or 0)
        rate = self.gaps / max(span / 60000.0, 1.0)
        return score((rate - GAPS_PER_MINUTE_OK) / GAPS_PER_MINUTE_OK)

    def replay(self) -> float:
        worst = 0.0
        for values in self.limbs.values():
            if len(values) < LIMB_MIN_SAMPLES:
                continue
            v = sorted(values)
            n = len(v)
            p10, p50, p90 = v[int(0.1 * (n - 1))], v[int(0.5 * (n - 1))], v[int(0.9 * (n - 1))]
            if p50 > 1e-6:
                worst = max(worst, (p90 - p10) / p50)
        return score((worst - LIMB_SPREAD_OK) / LIMB_SPREAD_RANGE)

    def summary(self) -> dict:
        return {"rows": self.rows, "continuity": self.continuity(), "replay": self.replay(),
                "gaps": self.gaps, "frozen": self.frozen}


def encode_trace(rows: list[list[int]]) -> str:
    raw = json.dumps({"v": 1, "fields": TRACE_FIELDS, "rows": rows}, separators=(",", ":")).encode()
    c = zlib.compressobj(6, zlib.DEFLATED, -15)
    return base64.b64encode(c.compress(raw) + c.flush()).decode()


def decode_trace(trace: str) -> list[list[int]] | None:
    try:
        data = json.loads(zlib.decompress(base64.b64decode(trace), -15))
        return data["rows"] if data.get("v") == 1 else None
    except Exception:  # noqa: BLE001 — any malformed trace is simply "no usable trace"
        return None


# ------------------------------------------------------------------------------------------------- server side
TRACE_WINDOW_MS = 100          # samples are 100 ms apart
TRACE_BOTTOM_MAX = SPEC["elbow"]["bottomMaxDeg"] + SPEC["elbow"]["hysteresisDeg"]   # 105
TRACE_TOP_MIN = SPEC["elbow"]["topMinDeg"] - 10                                      # 145
TRACE_MISMATCH_SHARE = 0.2


def trace_codes(log: dict) -> tuple[list[str], list[str]]:
    """(hard, soft) codes from the feature trace: every counted rep must show a real dip in the trace (elbow ≤ 105°
    inside the rep, ≥ 145° around its ends). > 20 % of reps without one → hard `trace_mismatch` (forged log)."""
    reps = log["reps"]
    if not reps:
        return [], []
    trace = log.get("featureTrace")
    rows = decode_trace(trace) if trace else None
    if not rows:
        return [], ["trace_missing"]
    bad = 0
    for r in reps:
        inside = [row for row in rows if r["tStartMs"] - TRACE_WINDOW_MS <= row[0] <= r["tEndMs"] + TRACE_WINDOW_MS]
        if len(inside) < 2:
            bad += 1
            continue
        dip = min(row[1] for row in inside) <= TRACE_BOTTOM_MAX
        top = max(row[1] for row in inside) >= TRACE_TOP_MIN
        if not (dip and top):
            bad += 1
    return (["trace_mismatch"] if bad > TRACE_MISMATCH_SHARE * len(reps) else []), []
