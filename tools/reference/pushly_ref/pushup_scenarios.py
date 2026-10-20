"""Synthetic RepEngine vectors: each scenario = timeline + the human label (what SHOULD happen).

The reference engine must reproduce every label exactly (test_reference.py); the platforms must reproduce the
reference events. Labels are what a coach would say, written before running the engine — never tuned to its output.
"""
from __future__ import annotations

import math

from .pose_synth import Pose, Segment, hold, rep, render


def reps(n: int, **kw) -> list[Segment]:
    out: list[Segment] = []
    for _ in range(n):
        out += rep(**kw)
    return out


def oscillate(n: int, low: float, high: float, period_ms: int, **pose) -> list[Segment]:
    out = []
    for _ in range(n):
        out += [Segment(period_ms // 2, high, low, Pose(**pose)), Segment(period_ms // 2, low, high, Pose(**pose))]
    return out


def head_bob(n: int) -> list[Segment]:
    return [hold(250, head_bob=0.08 * math.sin(k * 1.3)) for k in range(n)]


def worm(n: int) -> list[Segment]:
    return [hold(300, sag=0.25 * math.sin(k * 0.9)) for k in range(n)]


def shake(n: int) -> list[Segment]:
    return [hold(100, shift=(0.03 * math.sin(k * 2.1), 0.02 * math.cos(k * 1.7)), motion=0.6) for k in range(n)]


LEGS = tuple(range(25, 33))
EVERYTHING = tuple(range(33))

# id: (segments, render kwargs, tags, expected {counted, rejected?})
SCENARIOS: dict[str, tuple] = {
    "good-10-normal": ([hold(1000)] + reps(10), {}, ["normal"], {"counted": 10, "rejected": {}}),
    "good-4-slow": ([hold(1000)] + reps(4, down_ms=1500, bottom_ms=300, up_ms=1500), {}, ["slow"], {"counted": 4, "rejected": {}}),
    "good-8-fast": ([hold(1000)] + reps(8, down_ms=320, bottom_ms=60, up_ms=320, top_ms=250), {}, ["fast"],
                    {"counted": 8, "rejected": {}}),
    "good-6-facing-left": ([hold(1000)] + reps(6), {"facing_right": False}, ["mirrored"], {"counted": 6, "rejected": {}}),
    "good-6-25fps": ([hold(1000)] + reps(6), {"fps": 25}, ["25fps"], {"counted": 6, "rejected": {}}),
    "good-5-noisy": ([hold(1000)] + reps(5), {"img_noise": 0.004, "world_noise": 0.010}, ["noisy"], {"counted": 5, "rejected": {}}),
    "good-4-chest-to-floor": ([hold(1000)] + reps(4, bottom=70), {}, ["deep"], {"counted": 4, "rejected": {}}),
    "form-half-reps": ([hold(1000)] + reps(6, bottom=128), {}, ["form", "half"], {"counted": 0, "rejected": {"NOT_DEEP_ENOUGH": 6}}),
    "form-too-fast": ([hold(1000)] + reps(5, down_ms=210, bottom_ms=80, up_ms=110, top_ms=500, bottom=50), {}, ["form", "fast"],
                      {"counted": 0, "rejected": {"TOO_FAST": 5}}),
    "form-too-slow": ([hold(1000)] + reps(2, down_ms=5500, bottom_ms=600, up_ms=5500), {}, ["form", "slow"],
                      {"counted": 0, "rejected": {"TOO_SLOW": 2}}),
    "form-no-lockout": ([hold(1000), Segment(600, 175, 85, Pose())] + oscillate(4, 85, 140, 1400), {}, ["form", "lockout"],
                        {"counted": 0, "rejected": {"NO_LOCKOUT": 1}}),
    "form-hips-sagging": ([hold(1000)] + reps(5, sag=0.25), {}, ["form", "sag"], {"counted": 0, "rejected": {"HIPS_SAGGING": 5}}),
    "form-hips-piked": ([hold(1000)] + reps(5, sag=-0.25), {}, ["form", "pike"], {"counted": 0, "rejected": {"HIPS_PIKED": 5}}),
    "form-irregular": ([hold(1000)] + [Segment(500, 175, 110, Pose()), Segment(400, 110, 135, Pose()),
                                       Segment(500, 135, 85, Pose()), Segment(600, 85, 175, Pose()), hold(400)] * 3,
                       {}, ["form", "irregular"], {"counted": 0, "rejected": {"IRREGULAR_MOTION": 3}}),
    "mixed-session": ([hold(1000)] + reps(4) + reps(2, bottom=128) + reps(1, sag=0.25) + reps(3), {}, ["mixed"],
                      {"counted": 7, "rejected": {"NOT_DEEP_ENOUGH": 2, "HIPS_SAGGING": 1}}),
    "occlusion-mid-set": ([hold(1000)] + reps(3) + [hold(1200, hidden=EVERYTHING), hold(1000)] + reps(3), {}, ["occlusion"],
                          {"counted": 6, "rejected": {}}),
    "cheat-knee-pushups": ([hold(1000, posture="knees")] + reps(6, posture="knees"), {}, ["cheat", "knees"], {"counted": 0}),
    "cheat-arm-waving-lying": ([hold(1000, posture="lying")] + oscillate(8, 80, 175, 1200, posture="lying"), {},
                               ["cheat", "arm-waving"], {"counted": 0}),
    "cheat-sitting-elbows": ([hold(1000, posture="sitting")] + oscillate(8, 80, 175, 1200, posture="sitting"), {},
                             ["cheat", "sitting"], {"counted": 0}),
    "cheat-wall-pushups": ([hold(1000, posture="wall")] + oscillate(8, 80, 175, 1200, posture="wall"), {},
                           ["cheat", "wall"], {"counted": 0}),
    "cheat-head-bob": ([hold(1000)] + head_bob(40), {}, ["cheat", "head-bob"], {"counted": 0}),
    "cheat-worm": ([hold(1000)] + worm(30), {}, ["cheat", "worm"], {"counted": 0}),
    "cheat-phone-shaken-still-person": ([hold(1000)] + shake(80), {}, ["cheat", "phone-motion"], {"counted": 0}),
    "cheat-reps-while-phone-moves": ([hold(1000, motion=0.5)] + reps(5, motion=0.5), {}, ["cheat", "phone-motion"],
                                     {"counted": 0, "rejected": {"INTEGRITY": 5}}),
    "cheat-legs-out-of-frame": ([hold(1000, hidden=LEGS)] + reps(5, hidden=LEGS), {}, ["cheat", "framing"], {"counted": 0}),
}


def build(seed_base: int = 1000) -> dict[str, dict]:
    out = {}
    for k, (sid, (segments, kwargs, tags, expected)) in enumerate(SCENARIOS.items()):
        fps = kwargs.get("fps", 30)
        out[sid] = {
            "id": f"synthetic-{sid}",
            "specVersion": 1,
            "meta": {"placement": "side", "camera": "synthetic", "device": "pose_synth", "fps": fps,
                     "imageWidth": 1280, "imageHeight": 720, "tags": ["synthetic"] + tags,
                     "humanCount": expected["counted"], "labeller": "scenario", "notes": ""},
            "frames": render(segments, seed=seed_base + k, **kwargs),
            "expected": {**expected, "toleranceCounted": 0},
        }
    return out
