"""Battle results (doc 07 §2) and the hidden MMR (doc 08 §1, Glicko-2) — executable reference.

Battles are settled on the server from the per-rep events it received (`battle_events`, server time relative to the
battle start), capped by each player's verified rep log (D-051). Times are integer milliseconds; quality 0–100.

decide(mode, variant, a, b) → {"winner": "a"|"b"|None, "reason", "a": {...}, "b": {...}}
  a / b: list of reps {"t": tEndMs since start, "q": quality, "round": round index (best_of_3 only)}.
"""
from __future__ import annotations

import math

GAP_BEST_OF_3_MS = 2000      # a best-of-3 set ends after a pause > 2 s
GAP_ENDURANCE_MS = 3000      # an endurance set ends after a pause > 3 s
ROUND_CAP_MS = 90_000
SPEED_CAP_MS = 120_000
ENDURANCE_CAP_MS = 600_000
TURN_WINDOW_MS = 5000
TURN_LATENCY_MAX_MS = 500
TURNS_CAP = 200


def r_avg(qs: list[int]) -> int:
    return math.floor(sum(qs) / len(qs) + 0.5) if qs else 0


def _sorted(reps: list[dict]) -> list[dict]:
    return sorted(reps, key=lambda r: r["t"])


def _continuous(reps: list[dict], gap: int, cap: int) -> list[dict]:
    """Reps of the first continuous set: stops at the first pause > gap; only reps ending within cap of the start."""
    out: list[dict] = []
    for r in _sorted(reps):
        if r["t"] > cap:
            break
        if out and r["t"] - out[-1]["t"] > gap:
            break
        out.append(r)
    return out


def _side(reps: list[dict]) -> dict:
    return {"reps": len(reps), "avgQuality": r_avg([r["q"] for r in reps]), "lastT": reps[-1]["t"] if reps else None}


def _compare(a: dict, b: dict, keys: list[tuple[str, int]]) -> str | None:
    """keys: (field, direction) with +1 = higher wins, -1 = lower wins. None values lose."""
    for field, direction in keys:
        x, y = a[field], b[field]
        if x == y:
            continue
        if x is None:
            return "b"
        if y is None:
            return "a"
        return "a" if (x - y) * direction > 0 else "b"
    return None


def decide(mode: str, variant: dict, a: list[dict], b: list[dict]) -> dict:
    if mode == "max_reps":
        cap = int(variant.get("durationS", 60)) * 1000
        sa, sb = _side([r for r in a if r["t"] <= cap]), _side([r for r in b if r["t"] <= cap])
        winner = _compare(sa, sb, [("reps", 1), ("avgQuality", 1), ("lastT", -1)])
        return {"winner": winner, "reason": "reps" if winner else "draw", "a": sa, "b": sb}

    if mode == "speed":
        target = int(variant.get("targetReps", 20))
        out = {}
        for k, reps in (("a", a), ("b", b)):
            within = [r for r in _sorted(reps) if r["t"] <= SPEED_CAP_MS]
            side = _side(within[:target])
            side["finishT"] = within[target - 1]["t"] if len(within) >= target else None
            out[k] = side
        sa, sb = out["a"], out["b"]
        if sa["finishT"] is not None or sb["finishT"] is not None:
            winner = _compare(sa, sb, [("finishT", -1)])
            return {"winner": winner, "reason": "target" if winner else "draw", "a": sa, "b": sb}
        winner = _compare(sa, sb, [("reps", 1), ("lastT", -1)])
        return {"winner": winner, "reason": "reps" if winner else "draw", "a": sa, "b": sb}

    if mode == "endurance":
        sa = _side(_continuous(a, GAP_ENDURANCE_MS, ENDURANCE_CAP_MS))
        sb = _side(_continuous(b, GAP_ENDURANCE_MS, ENDURANCE_CAP_MS))
        winner = _compare(sa, sb, [("reps", 1), ("lastT", -1)])
        return {"winner": winner, "reason": "reps" if winner else "draw", "a": sa, "b": sb}

    if mode == "best_of_3":
        wins = {"a": 0, "b": 0}
        rounds = []
        totals = {"a": [], "b": []}
        for rnd in range(3):
            sets = {}
            for k, reps in (("a", a), ("b", b)):
                rr = [r for r in reps if r.get("round", 0) == rnd]
                first = min((r["t"] for r in rr), default=0)
                sets[k] = _continuous(rr, GAP_BEST_OF_3_MS, first + ROUND_CAP_MS)
                totals[k] += sets[k]
            na, nb = len(sets["a"]), len(sets["b"])
            rw = "a" if na > nb else "b" if nb > na else None
            if rw:
                wins[rw] += 1
            rounds.append({"a": na, "b": nb, "winner": rw})
            if max(wins.values()) >= 2:
                break
        sa, sb = _side(totals["a"]), _side(totals["b"])
        sa["rounds"], sb["rounds"] = wins["a"], wins["b"]
        winner = _compare(sa, sb, [("rounds", 1)])
        reason = "rounds"
        if winner is None:
            winner = _compare(sa, sb, [("reps", 1), ("avgQuality", 1)])
            reason = "reps" if winner else "draw"
        return {"winner": winner, "reason": reason, "a": sa, "b": sb, "rounds": rounds}

    if mode == "turns":
        # Merged timeline: players must alternate; each rep must end within the window after the other's last rep.
        events = sorted([dict(r, p="a") for r in a] + [dict(r, p="b") for r in b], key=lambda r: (r["t"], r["p"]))
        window = TURN_WINDOW_MS + min(int(variant.get("latencyMs", 0)), TURN_LATENCY_MAX_MS)
        counted = {"a": [], "b": []}
        loser, reason = None, "draw"
        prev = None
        for e in events:
            if prev is not None and e["p"] == prev["p"]:
                continue                     # an extra rep out of turn doesn't count (and doesn't lose)
            if prev is not None and e["t"] - prev["t"] > window:
                loser, reason = e["p"], "turn_missed"
                break
            counted[e["p"]].append(e)
            prev = e
            if len(counted["a"]) + len(counted["b"]) >= TURNS_CAP:
                break
        else:
            if prev is not None and len(counted["a"]) + len(counted["b"]) < TURNS_CAP:
                loser, reason = ("b" if prev["p"] == "a" else "a"), "turn_missed"   # the other side never answered
        sa, sb = _side(counted["a"]), _side(counted["b"])
        if loser:
            return {"winner": "b" if loser == "a" else "a", "reason": reason, "a": sa, "b": sb}
        winner = _compare(sa, sb, [("avgQuality", 1)]) if events else None
        return {"winner": winner, "reason": "quality" if winner else "draw", "a": sa, "b": sb}

    raise ValueError(mode)


# ---------------------------------------------------------------------------------------------------------------------
# Glicko-2 (Glickman 2013), one game per rating period. τ = 0.5, ε = 1e-6, rating scale factor 173.7178.
# ---------------------------------------------------------------------------------------------------------------------
TAU = 0.5
SCALE = 173.7178
EPS = 1e-6
RD_MAX = 350.0


def glicko2(rating: float, rd: float, vol: float, opponents: list[tuple[float, float, float]]) -> tuple[float, float, float]:
    """opponents: [(rating, rd, score)] with score 1 / 0.5 / 0. Returns new (rating, rd, vol)."""
    mu, phi = (rating - 1500) / SCALE, rd / SCALE
    if not opponents:
        return rating, min(RD_MAX, math.sqrt(phi * phi + vol * vol) * SCALE), vol

    def g(p: float) -> float:
        return 1 / math.sqrt(1 + 3 * p * p / (math.pi ** 2))

    def e(m: float, mj: float, pj: float) -> float:
        return 1 / (1 + math.exp(-g(pj) * (m - mj)))

    v_inv = 0.0
    delta_sum = 0.0
    for r_j, rd_j, s_j in opponents:
        mj, pj = (r_j - 1500) / SCALE, rd_j / SCALE
        ej = e(mu, mj, pj)
        v_inv += g(pj) ** 2 * ej * (1 - ej)
        delta_sum += g(pj) * (s_j - ej)
    v = 1 / v_inv
    delta = v * delta_sum

    a = math.log(vol * vol)

    def f(x: float) -> float:
        ex = math.exp(x)
        return ex * (delta * delta - phi * phi - v - ex) / (2 * (phi * phi + v + ex) ** 2) - (x - a) / (TAU * TAU)

    big_a = a
    if delta * delta > phi * phi + v:
        big_b = math.log(delta * delta - phi * phi - v)
    else:
        k = 1
        while f(a - k * TAU) < 0:
            k += 1
        big_b = a - k * TAU
    fa, fb = f(big_a), f(big_b)
    while abs(big_b - big_a) > EPS:
        c = big_a + (big_a - big_b) * fa / (fb - fa)
        fc = f(c)
        if fc * fb <= 0:
            big_a, fa = big_b, fb
        else:
            fa = fa / 2
        big_b, fb = c, fc
    new_vol = math.exp(big_a / 2)
    phi_star = math.sqrt(phi * phi + new_vol * new_vol)
    new_phi = 1 / math.sqrt(1 / (phi_star * phi_star) + 1 / v)
    new_mu = mu + new_phi * new_phi * delta_sum
    return new_mu * SCALE + 1500, min(RD_MAX, new_phi * SCALE), new_vol
