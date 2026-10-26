"""Battles for the recap vectors (minimal battle.schema.json shapes)."""


def _b(cid, me, winner, reason, a, b, *, mode="max_reps", status="settled", ranked=True, trophies=None):
    battle = {
        "id": cid, "type": "quick", "mode": mode, "variant": {}, "ranked": ranked, "status": status, "me": me,
        "opponent": {"username": "rival"}, "ready": {"a": True, "b": True}, "score": {"a": a.get("reps", 0), "b": b.get("reps", 0)},
        "winner": winner,
        "result": None if reason is None else {
            "winner": None if winner is None else (me if winner == "me" else ("b" if me == "a" else "a")),
            "reason": reason, "a": {"avgQuality": 80, "lastT": None, **a}, "b": {"avgQuality": 80, "lastT": None, **b},
            "trophies": trophies},
    }
    return battle


def side(reps, **kw):
    return {"reps": reps, **kw}


BATTLES = [
    _b("lost-by-one", "a", "opponent", "reps", side(24), side(25), trophies={"a": -18, "b": 18}),
    _b("won-by-five-as-b", "b", "me", "reps", side(20), side(25), trophies={"a": -20, "b": 20}),
    _b("won-by-one", "a", "me", "reps", side(31), side(30)),
    _b("speed-photo-finish", "a", "me", "target", side(20, finishT=41200), side(20, finishT=41600), mode="speed"),
    _b("speed-slow-loss", "a", "opponent", "target", side(20, finishT=52000), side(20, finishT=40000), mode="speed"),
    _b("speed-one-unfinished", "a", "opponent", "target", side(17), side(20, finishT=55000), mode="speed"),
    _b("bo3-two-one", "a", "me", "rounds", side(40, rounds=2), side(38, rounds=1), mode="best_of_3"),
    _b("bo3-sweep-loss", "a", "opponent", "rounds", side(30, rounds=0), side(45, rounds=2), mode="best_of_3"),
    _b("form-tiebreak", "a", "opponent", "quality", side(22), side(22)),
    _b("opponent-left", "a", "me", "forfeit", side(5), side(2)),
    _b("i-left", "a", "opponent", "forfeit", side(3), side(9)),
    _b("missed-turn", "b", "opponent", "turn_missed", side(14), side(12), mode="turns"),
    _b("draw", "a", None, "draw", side(18), side(18), ranked=False),
    _b("void", "a", None, None, {}, {}, status="void"),
]
