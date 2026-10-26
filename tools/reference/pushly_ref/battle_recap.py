"""Battle History recap (D-077): outcome, my/their reps, the margin and whether it was a close call.

Mirrors iOS `BattleRecap` and Android `BattleRecap`; vectors in shared/test-vectors/battles/recap.json.
"""
from __future__ import annotations


def recap(battle: dict) -> dict:
    me_a = battle["me"] == "a"
    winner = battle.get("winner")
    outcome = "win" if winner == "me" else "loss" if winner == "opponent" else "draw"
    r = battle.get("result")
    if r is None:
        score = battle["score"]
        mine, theirs = (score["a"], score["b"]) if me_a else (score["b"], score["a"])
        margin = {"kind": "void" if battle["status"] == "void" else "draw"}
        return {"outcome": outcome, "mine": mine, "theirs": theirs, "margin": margin, "close": is_close(margin)}
    me, them = (r["a"], r["b"]) if me_a else (r["b"], r["a"])
    lost = outcome == "loss"
    reason = r["reason"]
    if reason == "forfeit":
        margin = {"kind": "forfeit", "byMe": lost}
    elif reason == "turn_missed":
        margin = {"kind": "turnMissed", "byMe": lost}
    elif reason == "draw":
        margin = {"kind": "draw"}
    elif reason == "quality":
        margin = {"kind": "form"}
    elif reason == "rounds":
        margin = {"kind": "rounds", "mine": me.get("rounds") or 0, "theirs": them.get("rounds") or 0}
    elif reason == "target" and me.get("finishT") is not None and them.get("finishT") is not None:
        margin = {"kind": "time", "ms": abs(me["finishT"] - them["finishT"])}
    elif outcome == "draw" and reason != "target":
        margin = {"kind": "draw"}
    else:
        margin = {"kind": "reps", "n": abs(me["reps"] - them["reps"])}
    return {"outcome": outcome, "mine": me["reps"], "theirs": them["reps"], "margin": margin, "close": is_close(margin)}


def is_close(margin: dict) -> bool:
    k = margin["kind"]
    if k == "reps":
        return margin["n"] <= 1
    if k == "time":
        return margin["ms"] <= 1000
    if k == "rounds":
        return abs(margin["mine"] - margin["theirs"]) == 1
    return k in ("form", "draw")
