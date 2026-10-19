"""Reference implementation of Clan War rep counting with anti-farming caps (doc 09 §3)."""
from __future__ import annotations

FULL_CAP = 200      # reps 1..200 per member per UTC day count 100 %
HALF_CAP = 400      # reps 201..400 count 50 % (rounded down); beyond 400 count 0


def counted_total(raw_reps_day: int, low_trust: bool = False) -> int:
    """Counted war reps for a member's whole UTC day, given the raw verified reps of that day.
    Low-trust members (trust 30–49, doc 06 §1) count ×0.5, rounded down, applied to the day total."""
    if raw_reps_day < 0:
        raise ValueError("negative reps")
    full = min(raw_reps_day, FULL_CAP)
    half = max(0, min(raw_reps_day, HALF_CAP) - FULL_CAP)
    total = full + half // 2
    return total // 2 if low_trust else total


def counted_for_session(reps_today_before: int, new_reps: int, low_trust: bool = False) -> int:
    """Counted war reps added by one new session = difference of day totals.
    Using differences makes the day's result independent of how reps were split into sessions."""
    if new_reps < 0:
        raise ValueError("negative reps")
    return counted_total(reps_today_before + new_reps, low_trust) - counted_total(reps_today_before, low_trust)
