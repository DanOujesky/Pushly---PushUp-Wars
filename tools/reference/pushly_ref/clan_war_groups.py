"""Clan Wars v2 (D-078): groups of 2–4 clans, placement ranking and the rating change.

- Ranking: higher war score first; tie → more contributors (≥ 50 counted reps); tie → reached the score earlier
  (`scoreAt`, only when the score > 0); still tied → same rank (competition ranking 1, 1, 3).
- Rating: pairwise Elo — every other clan in the group is one "game": S = 1 for a better rank, 0.5 for the same rank,
  0 for a worse rank; Δ = round(Σ K · (S − E)), K = 30 per opponent, E = 1 / (1 + 10^((R_other − R_me) / 400)).
  So stakes grow with the number of opponents: equal clans ±15 in a duel, +45 / +15 / −15 / −45 in a group of four.
  Rounding is half away from zero (same as Postgres `round(numeric)`); ratings never drop below 0.
- Stakes shown before / during a war: what I gain finishing 1st (everyone else tied behind me) and lose finishing last.
- Group sizes when the week's clans are grouped: as even as possible, never more than 4, never a group of 1 when
  there are at least 2 clans (5 → 3 + 2, 9 → 3 + 3 + 3).
"""
from __future__ import annotations

import math

K = 30
MAX_GROUP = 4


def round_half_away(x: float) -> int:
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)


def expected(r_me: int, r_other: int) -> float:
    return 1 / (1 + 10 ** ((r_other - r_me) / 400))


def rank(entries: list[dict]) -> dict[str, int]:
    """entries: [{id, score, contributors, scoreAt (ms or None)}] → {id: rank}."""
    def key(e: dict) -> tuple:
        at = e.get("scoreAt") if e["score"] > 0 and e.get("scoreAt") is not None else math.inf
        return (-e["score"], -e["contributors"], at)
    ordered = sorted(entries, key=key)
    ranks: dict[str, int] = {}
    for i, e in enumerate(ordered):
        if i > 0 and key(e) == key(ordered[i - 1]):
            ranks[e["id"]] = ranks[ordered[i - 1]["id"]]
        else:
            ranks[e["id"]] = i + 1
    return ranks


def deltas(ratings: dict[str, int], ranks: dict[str, int]) -> dict[str, int]:
    out = {}
    for me, r_me in ratings.items():
        total = 0.0
        for other, r_other in ratings.items():
            if other == me:
                continue
            s = 1.0 if ranks[me] < ranks[other] else 0.5 if ranks[me] == ranks[other] else 0.0
            total += K * (s - expected(r_me, r_other))
        out[me] = round_half_away(total)
    return out


def stakes(ratings: dict[str, int], me: str) -> dict[str, int]:
    others = [r for cid, r in ratings.items() if cid != me]
    win = sum(K * (1 - expected(ratings[me], r)) for r in others)
    last = sum(K * (0 - expected(ratings[me], r)) for r in others)
    return {"win": round_half_away(win), "last": round_half_away(last)}


def group_sizes(n: int) -> list[int]:
    if n <= 0:
        return []
    g = math.ceil(n / MAX_GROUP)
    base, extra = divmod(n, g)
    return [base + 1] * extra + [base] * (g - extra)
