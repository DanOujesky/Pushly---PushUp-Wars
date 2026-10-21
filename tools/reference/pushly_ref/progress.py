"""XP, levels and achievements (doc 10 §4–5) — executable spec.

Server: SQL (app.level_for_xp, app.achievements_unlocked, migration *_progress.sql) is tested against the vectors
generated from this file (shared/test-vectors/progress). Apps only display levels (same math, same vectors).

- XP: 1 per verified rep, +20 per succeeded wake, + achievement XP (battle XP arrives with Phase 7).
- Level L needs threshold(L) = round(100 × (L − 1)^1.5) cumulative XP — level 1 at 0, level 2 at 100, 3 at 283 …
  (doc 10 §5 states "100 × n^1.5"; read as the XP to *leave* level n, D-048). Rounding = floor(x + 0.5).
- Achievements: data-driven rules over a user's facts (shared/achievements/definitions.json). Unknown rule types
  (battles, clans, social before their phases) simply never unlock.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

DEFINITIONS = json.loads((Path(__file__).resolve().parents[3] / "shared/achievements/definitions.json").read_text())
XP_PER_REP = 1
XP_PER_WAKE = 20
MAX_LEVEL = 200


def threshold(level: int) -> int:
    return int(math.floor(100 * (level - 1) ** 1.5 + 0.5))


def level_for_xp(xp: int) -> int:
    level = 1
    while level < MAX_LEVEL and threshold(level + 1) <= xp:
        level += 1
    return level


def level_progress(xp: int) -> dict:
    """{level, xpIntoLevel, xpForNext} — what the profile bar shows."""
    level = level_for_xp(xp)
    lo, hi = threshold(level), threshold(level + 1)
    return {"level": level, "xpIntoLevel": xp - lo, "xpForNext": hi - lo}


def rule_met(rule: dict, facts: dict) -> bool:
    t = rule["type"]
    if t == "wakes":
        return facts.get("wakes", 0) >= rule["min"]
    if t == "wakes_before":
        return facts.get("wakesBefore", {}).get(rule["localTime"], 0) >= rule["min"]
    if t == "wakes_mode":
        by_mode = facts.get("wakesByMode", {})
        return sum(by_mode.get(m, 0) for m in rule["modes"]) >= rule["min"]
    if t == "streak":
        return facts.get("bestStreak", 0) >= rule["min"]
    if t == "reps_total":
        return facts.get("repsTotal", 0) >= rule["min"]
    if t == "reps_day":
        return facts.get("maxDay", 0) >= rule["min"]
    if t == "best_set":
        return facts.get("bestSet", 0) >= rule["min"]
    if t == "sessions":
        return facts.get("sessions", 0) >= rule["min"]
    if t == "session_quality":
        return facts.get("bestAvgByMinReps", {}).get(str(rule["minReps"]), 0) >= rule["avgMin"]
    if t == "level":
        return facts.get("level", 1) >= rule["min"]
    return False  # battle_*, clan_*, friends, invites_joined: from later phases


def unlocked(facts: dict, already: list[str], definitions: list[dict] | None = None) -> list[str]:
    """Newly unlocked achievement ids, in definition order."""
    defs = definitions if definitions is not None else DEFINITIONS["definitions"]
    have = set(already)
    return [d["id"] for d in defs if d["id"] not in have and rule_met(d["rule"], facts)]


def fact_thresholds(definitions: list[dict] | None = None) -> dict:
    """Which wake-before times and session-quality rep minimums the facts must carry."""
    defs = definitions if definitions is not None else DEFINITIONS["definitions"]
    times = sorted({d["rule"]["localTime"] for d in defs if d["rule"]["type"] == "wakes_before"})
    reps = sorted({d["rule"]["minReps"] for d in defs if d["rule"]["type"] == "session_quality"})
    return {"wakeBefore": times, "qualityMinReps": reps}
