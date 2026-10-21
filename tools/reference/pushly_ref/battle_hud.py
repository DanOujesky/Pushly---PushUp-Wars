"""Live battle HUD clocks (doc 07 §2, §6; migration 0020). Executable reference for iOS + Android `BattleHud`.

Best of 3 runs on a fixed server clock: round r is the set window [r·135 s, r·135 s + 90 s), then 45 s rest; the
battle is over at 360 s. Turns: after a rep the other player has 5 s for the next one. All times are ms since the
battle start (server time). The server result (`app.decide_battle`) is still the authority.
"""
from __future__ import annotations

ROUND_MS = 135_000
SET_MS = 90_000
REST_MS = ROUND_MS - SET_MS
BO3_END_MS = 3 * ROUND_MS - REST_MS
TURN_MS = 5_000


def bo3_clock(t: int) -> dict:
    """{"round": 0..2, "phase": countdown | set | rest | over, "msLeft": ms until the phase ends}."""
    if t < 0:
        return {"round": 0, "phase": "countdown", "msLeft": -t}
    if t >= BO3_END_MS:
        return {"round": 2, "phase": "over", "msLeft": 0}
    r, within = divmod(t, ROUND_MS)
    if within < SET_MS:
        return {"round": r, "phase": "set", "msLeft": SET_MS - within}
    return {"round": r, "phase": "rest", "msLeft": ROUND_MS - within}


def bo3_clinched(my_sets: list[int], their_raw: list[int]) -> bool:
    """True when I have certainly won rounds 0 and 1: my set (continuous reps) beat the opponent's raw count, which is
    an upper bound of their set. Used to end the battle after round 2 instead of waiting for round 3."""
    return len(my_sets) >= 2 and len(their_raw) >= 2 and all(my_sets[i] > their_raw[i] for i in (0, 1))


def turn_state(t: int, my_last: int | None, their_last: int | None) -> dict:
    """{"turn": anyone | me | them, "msLeft": ms left in the current turn window (negative = overdue) or None}."""
    if my_last is None and their_last is None:
        return {"turn": "anyone", "msLeft": None}
    if their_last is None or (my_last is not None and my_last > their_last):
        return {"turn": "them", "msLeft": TURN_MS - (t - my_last)}
    return {"turn": "me", "msLeft": TURN_MS - (t - their_last)}
