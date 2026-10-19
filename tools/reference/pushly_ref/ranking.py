"""Reference implementation of trophies, leagues (doc 08 §2) and Wake Score (doc 08 §3).
Integer math only. `tdiv` = integer division truncating toward zero (Swift/Kotlin `/`, SQL integer `/`)."""
from __future__ import annotations

from dataclasses import asdict, dataclass

FLOORS = (600, 1200, 2000)
LEAGUES = (
    ("bronze", 0, 599), ("silver", 600, 1199), ("gold", 1200, 1999),
    ("platinum", 2000, 2999), ("diamond", 3000, 3999), ("champion", 4000, 4999),
)


def tdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def clamp(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def win_gain(me: int, opp: int) -> int:
    return clamp(30 + tdiv(opp - me, 25), 10, 50)


def loss_cost(me: int, opp: int) -> int:
    return clamp(20 - tdiv(opp - me, 25), 5, 40)


@dataclass
class TrophyState:
    trophies: int
    floor: int = 0                 # highest floor reached this season (0, 600, 1200, 2000)
    placement_left: int = 5
    win_streak: int = 0

    def to_json(self) -> dict:
        return asdict(self)


def apply_ranked_result(s: TrophyState, opp_trophies: int, outcome: str) -> tuple[TrophyState, int]:
    """outcome: 'win' | 'loss' | 'draw'. Returns (new state, delta actually applied)."""
    if outcome not in ("win", "loss", "draw"):
        raise ValueError(outcome)
    placement = s.placement_left > 0
    if outcome == "win":
        delta = win_gain(s.trophies, opp_trophies)
        if placement:
            delta = delta * 3 // 2               # ×1.5 rounded down
        streak = s.win_streak + 1
        if streak >= 3:
            delta += 3
    elif outcome == "loss":
        delta = -loss_cost(s.trophies, opp_trophies)
        if placement:
            delta = -(loss_cost(s.trophies, opp_trophies) // 2)  # ×0.5 rounded down (magnitude)
        streak = 0
    else:
        delta, streak = 0, s.win_streak

    new_trophies = max(s.floor, s.trophies + delta)
    applied = new_trophies - s.trophies
    floor = max([s.floor] + [f for f in FLOORS if new_trophies >= f])
    return TrophyState(
        trophies=new_trophies,
        floor=floor,
        placement_left=max(0, s.placement_left - 1),
        win_streak=streak,
    ), applied


def season_reset(trophies: int) -> int:
    return trophies if trophies <= 2000 else 2000 + tdiv(trophies - 2000, 2)


def league_for(trophies: int) -> dict:
    if trophies < 0:
        raise ValueError("negative trophies")
    if trophies >= 5000:
        return {"league": "legend", "tier": None}
    for name, lo, hi in LEAGUES:
        if lo <= trophies <= hi:
            if name == "champion":
                return {"league": name, "tier": None}
            size = (hi - lo + 1) // 3
            if trophies < lo + size:
                tier = "III"
            elif trophies < lo + 2 * size:
                tier = "II"
            else:
                tier = "I"
            return {"league": name, "tier": tier}
    raise AssertionError("unreachable")


def wake_points(mode_type: str, final_target_reps: int, avg_quality: int, snoozes_used: int = 0) -> int:
    base = 10
    difficulty = min(20, final_target_reps // 5)
    if mode_type in ("beatTheClock", "sprint", "sets"):
        mode_bonus = 3
    elif mode_type == "escalation":
        mode_bonus = -2 * snoozes_used
    elif mode_type == "ringUntilDone":
        mode_bonus = 0
    else:
        raise ValueError(mode_type)
    quality = 3 if avg_quality >= 90 else (1 if avg_quality >= 75 else 0)
    return max(5, base + difficulty + mode_bonus + quality)
