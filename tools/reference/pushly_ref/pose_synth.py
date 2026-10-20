"""Synthetic push-up pose sequences (side view) for RepEngine test vectors.

A small 2D kinematic body model (wrists and toes on the floor, rigid segments) produces the 33 BlazePose landmarks
in the same format MediaPipe emits: normalised image landmarks + hip-centred world landmarks. Scenarios cover good
reps and the cheat / bad-form types listed in doc 05 §8. They complement — never replace — recordings of real people
(roadmap P3-05): real vectors are collected with the pose recorder and committed under shared/test-vectors/pushup.

Deterministic: noise comes from random.Random(seed); the generated JSON is what both platforms read.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field, replace

# Body (metres)
UPPER_ARM, FOREARM = 0.30, 0.28
TORSO, THIGH, SHIN = 0.52, 0.45, 0.45
ANKLE = (0.0, 0.10)                 # pivot when on the toes
WRIST_Y = 0.03
SHOULDER_Z, HIP_Z = 0.19, 0.15      # half widths (left = -z = towards a camera on the subject's left)
IMAGE_W, IMAGE_H = 1280, 720
FOCAL = 600.0                       # px per metre at the subject's distance
FLOOR_V = 620.0
BODY_CENTRE_X = 0.70


@dataclass
class Pose:
    """Pose parameters for one frame."""
    elbow: float = 175.0            # degrees
    sag: float = 0.0                # metres hip offset perpendicular to the body line (+ = towards the floor)
    posture: str = "plank"          # plank | knees | sitting | wall | lying
    head_bob: float = 0.0           # metres
    shift: tuple[float, float] = (0.0, 0.0)   # image shift (normalised), e.g. a moving phone
    hidden: tuple[int, ...] = ()    # landmark indices with low visibility (occlusion / out of frame)
    motion: float | None = None     # device motion RMS (g)


def _circle_intersections(c0, r0, c1, r1):
    dx, dy = c1[0] - c0[0], c1[1] - c0[1]
    d = math.hypot(dx, dy)
    if d < 1e-9 or d > r0 + r1 or d < abs(r0 - r1):
        # Not reachable: clamp to the closest configuration along the centre line.
        k = r0 / max(d, 1e-9)
        return [(c0[0] + dx * k, c0[1] + dy * k)] * 2
    a = (r0 * r0 - r1 * r1 + d * d) / (2 * d)
    h = math.sqrt(max(r0 * r0 - a * a, 0.0))
    xm, ym = c0[0] + a * dx / d, c0[1] + a * dy / d
    return [(xm + h * dy / d, ym - h * dx / d), (xm - h * dy / d, ym + h * dx / d)]


def _arm_reach(theta: float) -> float:
    return math.sqrt(UPPER_ARM ** 2 + FOREARM ** 2 - 2 * UPPER_ARM * FOREARM * math.cos(math.radians(theta)))


def skeleton(p: Pose) -> dict[str, tuple[float, float]]:
    """2D side-view joints (x along the body, y up from the floor). The subject faces +x (head to the right)."""
    legs = THIGH + SHIN
    body = TORSO + legs
    wrist_x = math.sqrt(body ** 2 - (WRIST_Y + _arm_reach(180.0) - ANKLE[1]) ** 2)
    if p.posture in ("plank", "knees"):
        pivot = ANKLE
        radius = body
        if p.posture == "knees":
            pivot, radius = (ANKLE[0] + legs * 0.55, 0.06), TORSO + THIGH   # knees on the floor
        w = (wrist_x, WRIST_Y)
        cands = _circle_intersections(w, _arm_reach(p.elbow), pivot, radius)
        s = max(cands, key=lambda c: c[1])
        if p.posture == "knees":
            knee = pivot
            hip = (knee[0] + (s[0] - knee[0]) * THIGH / radius, knee[1] + (s[1] - knee[1]) * THIGH / radius)
            ankle = (knee[0] - SHIN, 0.20)
        else:
            ux, uy = (s[0] - pivot[0]) / radius, (s[1] - pivot[1]) / radius
            hip = (pivot[0] + ux * legs + uy * p.sag, pivot[1] + uy * legs - ux * p.sag)
            knee = ((pivot[0] + hip[0]) / 2, (pivot[1] + hip[1]) / 2)
            ankle = pivot
    elif p.posture == "lying":           # flat on the floor, waving the forearms
        s, hip, knee, ankle = (1.25, 0.12), (0.75, 0.11), (0.38, 0.09), (0.0, 0.08)
        w = None
    elif p.posture == "sitting":         # torso upright, legs forward on the floor
        hip, knee, ankle = (0.55, 0.12), (0.95, 0.14), (1.38, 0.08)
        s = (0.52, 0.12 + TORSO)
        w = None
    else:                                # wall: standing, body leaning ~70° from horizontal
        ankle, knee = (0.0, 0.08), (0.15, 0.50)
        hip = (0.30, 0.92)
        s = (0.48, 0.92 + TORSO * 0.95)
        w = None
    if w is None:
        # Forearm swings in front of the shoulder with the requested elbow angle.
        elbow = (s[0] + UPPER_ARM * 0.9, s[1] - UPPER_ARM * 0.4)
        ang = math.radians(180.0 - p.elbow)
        base = math.atan2(elbow[1] - s[1], elbow[0] - s[0])
        w = (elbow[0] + FOREARM * math.cos(base + ang), elbow[1] + FOREARM * math.sin(base + ang))
    else:
        e_cands = _circle_intersections(w, FOREARM, s, UPPER_ARM)
        elbow = min(e_cands, key=lambda c: c[0])        # elbows point back towards the feet
    head_dir = math.atan2(s[1] - hip[1], s[0] - hip[0])
    nose = (s[0] + 0.24 * math.cos(head_dir), s[1] + 0.24 * math.sin(head_dir) + 0.03 + p.head_bob)
    return {"s": s, "e": elbow, "w": w, "h": hip, "k": knee, "a": ankle, "n": nose}


def landmarks(p: Pose, rng: random.Random, facing_right: bool = True, img_noise=0.0015, world_noise=0.004):
    j = skeleton(p)
    sx = 1.0 if facing_right else -1.0
    near_z = -1.0  # the side nearest the camera
    # (x, y, z) per BlazePose index; z: left landmarks towards the camera when facing right.
    pts: dict[int, tuple[float, float, float]] = {}

    def put(i_left: int, i_right: int, xy, half_width: float):
        lz = near_z * half_width if facing_right else -near_z * half_width
        pts[i_left] = (xy[0], xy[1], lz)
        pts[i_right] = (xy[0], xy[1], -lz)

    put(11, 12, j["s"], SHOULDER_Z)
    put(13, 14, j["e"], SHOULDER_Z + 0.02)
    put(15, 16, j["w"], SHOULDER_Z)
    put(23, 24, j["h"], HIP_Z)
    put(25, 26, j["k"], HIP_Z * 0.8)
    put(27, 28, j["a"], HIP_Z * 0.7)
    put(29, 30, (j["a"][0] - 0.05, j["a"][1] - 0.04), HIP_Z * 0.7)
    put(31, 32, (j["a"][0] + 0.08, j["a"][1] - 0.07), HIP_Z * 0.7)
    for i, (dx, dy) in zip(range(17, 23), [(0.05, -0.01)] * 6):
        pts[i] = (j["w"][0] + dx, j["w"][1] + dy, pts[15 if i % 2 else 16][2])
    nose = j["n"]
    pts[0] = (nose[0], nose[1], 0.0)
    for i in range(1, 11):
        side = -1 if i in (1, 2, 3, 7, 9) else 1
        pts[i] = (nose[0] - 0.02, nose[1] + 0.02 - 0.01 * (i % 3), side * 0.04)

    hip_mid = j["h"]
    lm, w = [], []
    for i in range(33):
        x, y, z = pts[i]
        # Mirror horizontally around the body centre when the subject faces left.
        xi = BODY_CENTRE_X + sx * (x - BODY_CENTRE_X)
        u = IMAGE_W / 2 + (xi - BODY_CENTRE_X) * FOCAL
        v = FLOOR_V - y * FOCAL
        near = (z < 0) if facing_right else (z > 0)
        vis = 0.97 if near or abs(z) < 1e-9 else 0.88
        if i in p.hidden:
            vis = 0.15
        nx = u / IMAGE_W + p.shift[0] + rng.gauss(0, img_noise)
        ny = v / IMAGE_H + p.shift[1] + rng.gauss(0, img_noise)
        lm.append([round(nx, 5), round(ny, 5), round(z, 4), vis, 0.99])
        wx = sx * (x - hip_mid[0]) + rng.gauss(0, world_noise)
        wy = -(y - hip_mid[1]) + rng.gauss(0, world_noise)
        wz = z + rng.gauss(0, world_noise)
        w.append([round(wx, 4), round(wy, 4), round(wz, 4)])
    return lm, w


# ----------------------------------------------------------------------------- timelines
@dataclass
class Segment:
    ms: int
    elbow_from: float
    elbow_to: float
    pose: Pose = field(default_factory=Pose)


def hold(ms: int, elbow: float = 175.0, **kw) -> Segment:
    return Segment(ms, elbow, elbow, Pose(**kw))


def rep(down_ms=600, bottom_ms=120, up_ms=600, top_ms=400, bottom=85.0, top=175.0, **kw) -> list[Segment]:
    return [Segment(down_ms, top, bottom, Pose(**kw)), Segment(bottom_ms, bottom, bottom, Pose(**kw)),
            Segment(up_ms, bottom, top, Pose(**kw)), Segment(top_ms, top, top, Pose(**kw))]


def render(segments: list[Segment], seed: int, fps: int = 30, facing_right: bool = True, **noise) -> list[dict]:
    rng = random.Random(seed)
    frames = []
    step = 1000.0 / fps
    t = 0.0
    for seg in segments:
        n = max(1, round(seg.ms / step))
        for k in range(n):
            u = k / n
            ease = (1 - math.cos(math.pi * u)) / 2
            elbow = seg.elbow_from + (seg.elbow_to - seg.elbow_from) * ease
            pose = replace(seg.pose, elbow=elbow)
            lm, w = landmarks(pose, rng, facing_right, **noise)
            frame = {"t": int(round(t)), "lm": lm, "w": w}
            if pose.motion is not None:
                frame["motion"] = round(pose.motion + abs(rng.gauss(0, 0.01)), 3)
            frames.append(frame)
            t += step
    return frames
