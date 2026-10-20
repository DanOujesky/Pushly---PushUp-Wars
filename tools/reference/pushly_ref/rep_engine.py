"""Reference RepEngine (doc 05 §4–5) — the executable specification of push-up counting.

Swift (`ios/Packages/RepEngine`) and Kotlin (`android/engine/rep`) implement exactly this algorithm and must produce
the same events for every vector in shared/test-vectors/pushup. Constants come only from
shared/rep-engine-spec/pushup-v1.yaml. Pure Python, no numpy, so every line maps 1:1 to the platform code.

Conventions
- Input per frame: t (ms), lm[33] = (x, y, z, visibility, presence) normalised image coords (un-mirrored, upright
  image, y down), w[33] = (x, y, z) world metres (hip-centred, y down), optional motion = device motion RMS in g.
- Image width/height come from the session (vector meta) and turn normalised coords into pixels.
- Rounding: quality = floor(100 * q + 0.5).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path

import yaml

SPEC = yaml.safe_load((Path(__file__).resolve().parents[3] / "shared/rep-engine-spec/pushup-v1.yaml").read_text())

# BlazePose indices: (shoulder, elbow, wrist, hip, knee, ankle) per side.
SIDES = {"left": (11, 13, 15, 23, 25, 27), "right": (12, 14, 16, 24, 26, 28)}

NOT_READY, TOP, DESCENDING, BOTTOM, ASCENDING, RECOVER = "notReady", "top", "descending", "bottom", "ascending", "recover"


# ----------------------------------------------------------------------------- math
def angle(a, b, c) -> float:
    """Angle at b in degrees (works for 2D or 3D points). Degenerate → 180."""
    ba = [a[i] - b[i] for i in range(len(a))]
    bc = [c[i] - b[i] for i in range(len(c))]
    na = math.sqrt(sum(v * v for v in ba))
    nc = math.sqrt(sum(v * v for v in bc))
    if na < 1e-9 or nc < 1e-9:
        return 180.0
    cos = sum(ba[i] * bc[i] for i in range(len(ba))) / (na * nc)
    cos = max(-1.0, min(1.0, cos))
    return math.degrees(math.acos(cos))


def dist(a, b) -> float:
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(len(a))))


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, v))


def median(values: list[float]) -> float:
    s = sorted(values)
    n = len(s)
    if n == 0:
        return 0.0
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


class OneEuro:
    """One-Euro filter for one scalar (Casiez et al.). dt in seconds."""

    def __init__(self, min_cutoff: float, beta: float, d_cutoff: float):
        self.min_cutoff, self.beta, self.d_cutoff = min_cutoff, beta, d_cutoff
        self.x = None
        self.dx = 0.0

    @staticmethod
    def alpha(cutoff: float, dt: float) -> float:
        tau = 1.0 / (2.0 * math.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)

    def __call__(self, value: float, dt: float) -> float:
        if self.x is None:
            self.x = value
            return value
        dx = (value - self.x) / dt
        self.dx = self.dx + self.alpha(self.d_cutoff, dt) * (dx - self.dx)
        cutoff = self.min_cutoff + self.beta * abs(self.dx)
        self.x = self.x + self.alpha(cutoff, dt) * (value - self.x)
        return self.x


# ----------------------------------------------------------------------------- features
@dataclass
class Features:
    t: int
    side: str
    vis: float
    elbow: float
    body_line: float
    knee: float
    hip_dev: float          # pixels, > 0 = hip below the shoulder–ankle line (sagging)
    torso_tilt: float
    bbox: float
    shoulder_y: float       # pixels
    upper_arm: float        # pixels
    placement: str          # side | front | unknown
    motion: float | None


@dataclass
class RepEvent:
    kind: str               # counted | rejected
    t: int
    reason: str | None = None
    index: int | None = None
    quality: int | None = None
    t_start: int | None = None
    t_bottom: int | None = None

    def to_json(self) -> dict:
        d = {"type": self.kind, "t": self.t}
        if self.kind == "counted":
            d.update({"index": self.index, "quality": self.quality, "tStart": self.t_start, "tBottom": self.t_bottom})
        else:
            d["reason"] = self.reason
        return d


@dataclass
class RepEngine:
    image_w: float
    image_h: float
    spec: dict = field(default_factory=lambda: SPEC)

    def __post_init__(self):
        s = self.spec
        oe = s["smoothing"]["oneEuro"]
        self._filters: dict[tuple, OneEuro] = {}
        self._oe = (oe["minCutoff"], oe["beta"], oe["dCutoff"])
        self.state = NOT_READY
        self.side: str | None = None
        self._switch_frames = 0
        self._last_t: int | None = None
        self._counts: dict[str, int] = {}
        self._low_vis_since: int | None = None
        self._off_plank_since: int | None = None
        self._top_shoulder_y = 0.0
        self._arm_samples: list[float] = []
        self._arm_ref = 0.0
        self._rep: list[Features] = []
        self._rep_start = 0
        self._t_bottom = 0
        self._asc_start = 0
        self._pending_first: Features | None = None
        self.counted = 0
        self.events: list[RepEvent] = []

    # ------------------------------------------------------------------ smoothing
    def _smooth(self, key: tuple, value: float, dt: float) -> float:
        f = self._filters.get(key)
        if f is None:
            f = OneEuro(*self._oe)
            self._filters[key] = f
        return f(value, dt)

    # ------------------------------------------------------------------ features
    def features(self, frame: dict) -> Features:
        t = int(frame["t"])
        dt = (t - self._last_t) / 1000.0 if self._last_t is not None and t > self._last_t else 1.0 / 30.0
        self._last_t = t
        lm, w = frame["lm"], frame["w"]
        img = []
        world = []
        for i in range(33):
            x = self._smooth(("ix", i), lm[i][0], dt) * self.image_w
            y = self._smooth(("iy", i), lm[i][1], dt) * self.image_h
            img.append((x, y))
            world.append((self._smooth(("wx", i), w[i][0], dt), self._smooth(("wy", i), w[i][1], dt),
                          self._smooth(("wz", i), w[i][2], dt)))
        vis = [lm[i][3] for i in range(33)]
        req = self.spec["visibility"]["requiredLandmarkMin"]

        def side_vis(name: str) -> float:
            sh, el, wr, hip, kn, an = SIDES[name]
            return min(vis[sh], vis[el], vis[wr], vis[hip], max(vis[kn], vis[an]))

        vl, vr = side_vis("left"), side_vis("right")
        if self.side is None:
            self.side = "left" if vl >= vr else "right"
        else:
            cur, other = (vl, vr) if self.side == "left" else (vr, vl)
            if other - cur > self.spec["stability"]["sideSwitchVisibilityDelta"]:
                self._switch_frames += 1
                if self._switch_frames >= self.spec["stability"]["sideSwitchFrames"]:
                    self.side = "right" if self.side == "left" else "left"
                    self._switch_frames = 0
            else:
                self._switch_frames = 0
        sv = vl if self.side == "left" else vr
        sh, el, wr, hip, kn, an = SIDES[self.side]
        ankle_ok = vis[an] >= req
        end = an if ankle_ok else kn

        elbow = angle(world[sh], world[el], world[wr])
        body_line = angle(world[sh], world[hip], world[end])
        knee = angle(world[hip], world[kn], world[an]) if ankle_ok else 180.0

        a, b, h = img[sh], img[end], img[hip]
        if abs(b[0] - a[0]) > 1e-6:
            y_line = a[1] + (b[1] - a[1]) * (h[0] - a[0]) / (b[0] - a[0])
        else:
            y_line = h[1]
        hip_dev = h[1] - y_line
        torso_tilt = math.degrees(math.atan2(abs(b[1] - a[1]), abs(b[0] - a[0])))

        bmin = self.spec["framing"]["bboxVisibilityMin"]
        pts = [(lm[i][0], lm[i][1]) for i in range(33) if vis[i] >= bmin]
        if pts:
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            bbox = max(max(xs) - min(xs), max(ys) - min(ys))
        else:
            bbox = 0.0

        sh_mid = ((img[11][0] + img[12][0]) / 2, (img[11][1] + img[12][1]) / 2)
        hip_mid = ((img[23][0] + img[24][0]) / 2, (img[23][1] + img[24][1]) / 2)
        torso_len = dist(sh_mid, hip_mid)
        ratio = dist(img[11], img[12]) / torso_len if torso_len > 1e-6 else 99.0
        fr = self.spec["framing"]
        placement = "side" if ratio < fr["placementSideMaxRatio"] else "front" if ratio > fr["placementFrontMinRatio"] else "unknown"

        return Features(t=t, side=self.side, vis=sv, elbow=elbow, body_line=body_line, knee=knee, hip_dev=hip_dev,
                        torso_tilt=torso_tilt, bbox=bbox, shoulder_y=img[sh][1], upper_arm=dist(img[sh], img[el]),
                        placement=placement, motion=frame.get("motion"))

    # ------------------------------------------------------------------ helpers
    def _stable(self, name: str, cond: bool) -> bool:
        """True once `cond` held for `stableFrames` consecutive frames (then the counter resets)."""
        if not cond:
            self._counts[name] = 0
            return False
        self._counts[name] = self._counts.get(name, 0) + 1
        if self._counts[name] >= self.spec["stability"]["stableFrames"]:
            self._counts[name] = 0
            return True
        return False

    def _enter(self, state: str) -> None:
        self.state = state
        self._counts = {}

    def _bottom_max(self, f: Features) -> float:
        e = self.spec["elbow"]
        return e["frontBottomMaxDeg"] if f.placement == "front" else e["bottomMaxDeg"]

    def _depth(self, f: Features) -> float:
        return (f.shoulder_y - self._top_shoulder_y) / self._arm_ref if self._arm_ref > 1e-6 else 0.0

    def _update_top(self, f: Features) -> None:
        self._top_shoulder_y = f.shoulder_y
        self._arm_samples.append(f.upper_arm)
        if len(self._arm_samples) > 30:
            self._arm_samples.pop(0)
        self._arm_ref = median(self._arm_samples)

    def _reject(self, reason: str, t: int) -> None:
        self.events.append(RepEvent("rejected", t, reason=reason))

    # ------------------------------------------------------------------ main step
    def process(self, frame: dict) -> list[RepEvent]:
        before = len(self.events)
        f = self.features(frame)
        s = self.spec
        e = s["elbow"]

        # Tracking / plank loss (≥ trackingLostMs) → NOT_READY from any state.
        lost_ms = s["stability"]["trackingLostMs"]
        if f.vis < s["visibility"]["lostBelow"]:
            self._low_vis_since = f.t if self._low_vis_since is None else self._low_vis_since
        else:
            self._low_vis_since = None
        if f.torso_tilt > s["plank"]["torsoTiltMaxDeg"]:
            self._off_plank_since = f.t if self._off_plank_since is None else self._off_plank_since
        else:
            self._off_plank_since = None
        vis_lost = self._low_vis_since is not None and f.t - self._low_vis_since >= lost_ms
        plank_lost = self._off_plank_since is not None and f.t - self._off_plank_since >= lost_ms
        if self.state != NOT_READY and (vis_lost or plank_lost):
            if self.state in (DESCENDING, BOTTOM, ASCENDING) and vis_lost:
                self._reject("BODY_NOT_VISIBLE", f.t)
            self._rep = []
            self._enter(NOT_READY)
            return self.events[before:]

        if self.state == NOT_READY:
            p = s["plank"]
            plank = (f.torso_tilt <= p["torsoTiltMaxDeg"] and f.body_line >= p["bodyLineMinDeg"]
                     and f.elbow >= e["topMinDeg"] and f.vis >= s["visibility"]["requiredLandmarkMin"]
                     and p["bboxHeightMin"] <= f.bbox <= p["bboxHeightMax"] and f.placement != "unknown")
            if self._stable("plank", plank):
                self._arm_samples = []
                self._update_top(f)
                self._enter(TOP)

        elif self.state == TOP:
            cond = f.elbow < e["topMinDeg"] - e["hysteresisDeg"]
            if cond and self._counts.get("down", 0) == 0:
                self._pending_first = f
            if self._stable("down", cond):
                first = self._pending_first or f
                self._rep = [first] if first is not f else []
                self._rep.append(f)
                self._rep_start = first.t
                self._enter(DESCENDING)
            elif not cond:
                self._update_top(f)

        elif self.state == DESCENDING:
            self._rep.append(f)
            if self._stable("bottom", f.elbow <= self._bottom_max(f) and self._depth(f) >= s["depth"]["minDepthRatio"]):
                self._t_bottom = f.t
                self._enter(BOTTOM)
            elif self._stable("upNoBottom", f.elbow >= e["topMinDeg"]):
                self._reject("NOT_DEEP_ENOUGH", f.t)
                self._rep = []
                self._update_top(f)
                self._enter(TOP)

        elif self.state == BOTTOM:
            self._rep.append(f)
            if self._stable("up", f.elbow > self._bottom_max(f) + e["hysteresisDeg"]):
                self._asc_start = f.t
                self._enter(ASCENDING)

        elif self.state == ASCENDING:
            self._rep.append(f)
            if self._stable("lockout", f.elbow >= e["topMinDeg"]):
                self._evaluate(f.t)
                self._rep = []
                self._update_top(f)
                self._enter(TOP)
            elif f.t - self._asc_start > e["lockoutWaitMs"] or self._stable("downAgain", f.elbow <= self._bottom_max(f)):
                self._reject("NO_LOCKOUT", f.t)
                self._rep = []
                self._enter(RECOVER)

        elif self.state == RECOVER:
            if self._stable("recovered", f.elbow >= e["topMinDeg"]):
                self._update_top(f)
                self._enter(TOP)

        return self.events[before:]

    # ------------------------------------------------------------------ evaluation (doc 05 §5)
    def _evaluate(self, t_end: int) -> None:
        s = self.spec
        frames = self._rep
        n = len(frames)
        if n == 0:
            return
        req = s["visibility"]["requiredLandmarkMin"]
        if sum(1 for f in frames if f.vis >= req) / n < s["visibility"]["requiredFrameShare"]:
            return self._reject("BODY_NOT_VISIBLE", t_end)
        if sum(1 for f in frames if f.knee >= s["form"]["kneeMinDeg"]) / n < s["form"]["kneeFrameShare"]:
            return self._reject("KNEES_DOWN", t_end)
        bad = [f for f in frames if f.body_line < s["form"]["bodyLineMinDeg"]]
        if (n - len(bad)) / n < s["form"]["bodyLineFrameShare"]:
            mean_dev = sum(f.hip_dev for f in bad) / len(bad)
            return self._reject("HIPS_SAGGING" if mean_dev > 0 else "HIPS_PIKED", t_end)
        duration = t_end - self._rep_start
        if duration < s["tempo"]["minRepMs"]:
            return self._reject("TOO_FAST", t_end)
        if duration > s["tempo"]["maxRepMs"]:
            return self._reject("TOO_SLOW", t_end)
        if reversals([f.elbow for f in frames], s["form"]["maxDirectionReversalsDeg"]) > 1:
            return self._reject("IRREGULAR_MOTION", t_end)
        motions = [f.motion for f in frames if f.motion is not None]
        if motions:
            shaky = sum(1 for m in motions if m > s["integrity"]["deviceMotionMaxRms"]) / len(motions)
            if shaky > s["integrity"]["deviceMotionFrameShare"]:
                return self._reject("INTEGRITY", t_end)

        e = s["elbow"]
        max_depth = max(self._depth(f) for f in frames)
        max_elbow = max(f.elbow for f in frames)
        mean_line = sum(f.body_line for f in frames) / n
        depth_s = clamp01((max_depth - s["depth"]["minDepthRatio"]) / 0.40)
        lock_s = clamp01((max_elbow - e["topMinDeg"]) / 20.0)
        line_s = clamp01((mean_line - s["form"]["bodyLineMinDeg"]) / 25.0)
        if duration < 1000:
            tempo_s = clamp01((duration - s["tempo"]["minRepMs"]) / 550.0)
        elif duration <= 3000:
            tempo_s = 1.0
        else:
            tempo_s = clamp01(1.0 - (duration - 3000) / 5000.0)
        wts = s["quality"]["weights"]
        q = wts["depth"] * depth_s + wts["lockout"] * lock_s + wts["bodyLine"] * line_s + wts["tempo"] * tempo_s
        self.counted += 1
        self.events.append(RepEvent("counted", t_end, index=self.counted, quality=int(math.floor(100 * q + 0.5)),
                                    t_start=self._rep_start, t_bottom=self._t_bottom))


def reversals(values: list[float], threshold: float) -> int:
    """Direction changes of a sequence, ignoring wiggles smaller than `threshold` (zig-zag filter)."""
    if not values:
        return 0
    ref = values[0]
    direction = 0  # 0 = undecided, 1 = rising, -1 = falling
    count = 0
    for v in values[1:]:
        if direction == 0:
            if v - ref >= threshold:
                direction, ref = 1, v
            elif ref - v >= threshold:
                direction, ref = -1, v
        elif direction == 1:
            if v > ref:
                ref = v
            elif ref - v >= threshold:
                count, direction, ref = count + 1, -1, v
        else:
            if v < ref:
                ref = v
            elif v - ref >= threshold:
                count, direction, ref = count + 1, 1, v
    return count


def run(vector: dict) -> dict:
    """Runs a vector and returns {counted, rejected, events} in the vector's `expected` shape."""
    meta = vector["meta"]
    engine = RepEngine(meta["imageWidth"], meta["imageHeight"])
    for frame in vector["frames"]:
        engine.process(frame)
    rejected: dict[str, int] = {}
    for ev in engine.events:
        if ev.kind == "rejected":
            rejected[ev.reason] = rejected.get(ev.reason, 0) + 1
    return {"counted": engine.counted, "rejected": dict(sorted(rejected.items())),
            "events": [ev.to_json() for ev in engine.events]}
