#!/usr/bin/env python3
"""Build shared/test-vectors from the reference implementations.

    python3 tools/reference/build_vectors.py          # (re)write vectors
    python3 tools/reference/build_vectors.py --check  # CI: fail if vectors differ from the reference

Changing an expected value is a rule change: it needs a decisions-log entry (shared/test-vectors/README.md).
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from pushly_ref import account, clan_war, ranking  # noqa: E402
from pushly_ref.occurrences import all_occurrences, challenge_occurrence  # noqa: E402
from pushly_ref.plan import android_next, ios_plan, os_alarm_id  # noqa: E402
from pushly_ref.validation import validate_schedule  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "shared/test-vectors"
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def utc(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def alarm(id_: str, *, kind="weekly", times=None, one_off=None, overrides=(), pause=None,
          enabled=True, counts=True, mode=None) -> dict:
    s = {
        "id": id_, "version": 1, "label": "Wake up", "enabled": enabled, "countsForChallenge": counts,
        "kind": kind, "overrides": list(overrides), "pause": pause,
        "mode": mode or {"type": "ringUntilDone", "targetReps": 20},
        "sound": {"id": "bundled.rooster_rush"},
    }
    if kind == "weekly":
        s["weekly"] = {d: (times or {}).get(d) for d in DAYS}
    else:
        s["oneOff"] = one_off
    return s


def every_day(t: str) -> dict:
    return {d: t for d in DAYS}


A = "a0000000-0000-4000-8000-000000000001"
B = "b0000000-0000-4000-8000-000000000002"
C = "c0000000-0000-4000-8000-000000000003"

OCCURRENCE_CASES = [
    ("prague-weekly-different-times", "Europe/Prague", "2026-10-18T22:00:00Z", 6,
     [alarm(A, times={"mon": "06:30", "tue": "07:15", "thu": "06:30", "fri": "06:30", "sat": "09:00"})]),
    ("prague-spring-forward-gap-0230", "Europe/Prague", "2027-03-27T12:00:00Z", 2, [alarm(A, times=every_day("02:30"))]),
    ("prague-spring-forward-gap-0200", "Europe/Prague", "2027-03-27T12:00:00Z", 1, [alarm(A, times=every_day("02:00"))]),
    ("prague-spring-forward-0300-ok", "Europe/Prague", "2027-03-27T12:00:00Z", 1, [alarm(A, times=every_day("03:00"))]),
    ("prague-fall-back-overlap-0230", "Europe/Prague", "2026-10-24T12:00:00Z", 2, [alarm(A, times=every_day("02:30"))]),
    ("prague-fall-back-0100-unaffected", "Europe/Prague", "2026-10-24T12:00:00Z", 1, [alarm(A, times=every_day("01:00"))]),
    ("prague-override-on-dst-day", "Europe/Prague", "2027-03-26T12:00:00Z", 3,
     [alarm(A, times=every_day("06:30"), overrides=[{"date": "2027-03-28", "time": "02:15"}])]),
    ("new-york-spring-forward", "America/New_York", "2027-03-13T12:00:00Z", 1, [alarm(A, times=every_day("02:10"))]),
    ("new-york-fall-back", "America/New_York", "2026-10-31T12:00:00Z", 1, [alarm(A, times=every_day("01:30"))]),
    ("kolkata-half-hour-offset", "Asia/Kolkata", "2026-10-18T00:00:00Z", 2, [alarm(A, times=every_day("06:30"))]),
    ("lord-howe-30min-dst-start", "Australia/Lord_Howe", "2026-10-03T00:00:00Z", 1, [alarm(A, times=every_day("02:15"))]),
    ("lord-howe-30min-dst-end", "Australia/Lord_Howe", "2027-04-03T00:00:00Z", 1, [alarm(A, times=every_day("01:45"))]),
    ("kiritimati-utc-plus-14", "Pacific/Kiritimati", "2026-10-19T00:00:00Z", 1, [alarm(A, times=every_day("06:00"))]),
    ("pago-pago-utc-minus-11", "Pacific/Pago_Pago", "2026-10-19T00:00:00Z", 1, [alarm(A, times=every_day("06:00"))]),
    ("override-time-and-skip", "Europe/Prague", "2026-10-19T12:00:00Z", 6,
     [alarm(A, times=every_day("06:30"), overrides=[{"date": "2026-10-21", "time": "05:40"},
                                                    {"date": "2026-10-22", "skip": True}])]),
    ("override-adds-day-without-weekly-time", "Europe/Prague", "2026-10-19T12:00:00Z", 6,
     [alarm(A, times={"mon": "06:30"}, overrides=[{"date": "2026-10-24", "time": "10:00"}])]),
    ("pause-inclusive-boundaries", "Europe/Prague", "2026-10-19T12:00:00Z", 8,
     [alarm(A, times=every_day("06:30"), pause={"from": "2026-10-21", "to": "2026-10-23"})]),
    ("pause-beats-override", "Europe/Prague", "2026-10-19T12:00:00Z", 4,
     [alarm(A, times=every_day("06:30"), overrides=[{"date": "2026-10-21", "time": "05:00"}],
            pause={"from": "2026-10-21", "to": "2026-10-21"})]),
    ("one-off-in-horizon", "Europe/Prague", "2026-10-19T12:00:00Z", 7, [alarm(A, kind="oneOff", one_off="2026-10-23T05:40")]),
    ("one-off-outside-horizon", "Europe/Prague", "2026-10-19T12:00:00Z", 2, [alarm(A, kind="oneOff", one_off="2026-10-30T05:40")]),
    ("one-off-in-past", "Europe/Prague", "2026-10-19T12:00:00Z", 7, [alarm(A, kind="oneOff", one_off="2026-10-19T05:40")]),
    ("disabled-alarm-never-rings", "Europe/Prague", "2026-10-19T12:00:00Z", 7, [alarm(A, times=every_day("06:30"), enabled=False)]),
    ("today-already-passed", "Europe/Prague", "2026-10-19T05:00:00Z", 1, [alarm(A, times=every_day("06:30"))]),
    ("from-equals-occurrence-is-excluded", "Europe/Prague", "2026-10-19T04:30:00Z", 1, [alarm(A, times=every_day("06:30"))]),
    ("horizon-zero-only-today", "Europe/Prague", "2026-10-19T02:00:00Z", 0, [alarm(A, times=every_day("06:30"))]),
    ("midnight-alarm", "Europe/Prague", "2026-10-19T12:00:00Z", 2, [alarm(A, times=every_day("00:00"))]),
    ("challenge-earliest-counting-alarm-wins", "Europe/Prague", "2026-10-18T12:00:00Z", 2,
     [alarm(A, times=every_day("07:00")), alarm(B, times=every_day("06:00"), counts=False),
      alarm(C, times=every_day("06:45"))]),
    ("challenge-tie-broken-by-alarm-id", "Europe/Prague", "2026-10-18T12:00:00Z", 1,
     [alarm(B, times=every_day("06:30")), alarm(A, times=every_day("06:30"))]),
    ("challenge-none-when-only-practice-alarms", "Europe/Prague", "2026-10-18T12:00:00Z", 1,
     [alarm(A, times=every_day("06:30"), counts=False)]),
    ("challenge-skip-moves-to-later-alarm", "Europe/Prague", "2026-10-18T12:00:00Z", 1,
     [alarm(A, times=every_day("06:00"), overrides=[{"date": "2026-10-19", "skip": True}]),
      alarm(C, times=every_day("07:30"))]),
]


def build_occurrence_vectors() -> dict[str, dict]:
    files = {}
    for cid, tz, frm, horizon, schedules in OCCURRENCE_CASES:
        from_dt = utc(frm)
        occ = all_occurrences(schedules, from_dt, tz, horizon)
        local_dates = sorted({o.local_date for o in occ})
        challenge = {d.isoformat(): (c.occurrence_id if (c := challenge_occurrence(d, occ)) else None) for d in local_dates}
        files[f"alarm-occurrences/{cid}.json"] = {
            "id": cid, "timeZone": tz, "from": frm, "horizonDays": horizon, "schedules": schedules,
            "expected": {"occurrences": [o.to_json() for o in occ], "challengeByLocalDate": challenge},
        }
    return files


def build_plan_vectors() -> dict[str, dict]:
    """Same inputs as the occurrence vectors; iOS window = horizonDays, 3 nags (doc 04 §5.2)."""
    cases = []
    for cid, tz, frm, horizon, schedules in OCCURRENCE_CASES:
        from_dt = utc(frm)
        cases.append({
            "id": cid, "timeZone": tz, "from": frm, "windowDays": horizon, "nagCount": 3, "schedules": schedules,
            "expected": {"ios": ios_plan(schedules, from_dt, tz, horizon, 3),
                         "androidNext": android_next(schedules, from_dt, tz)},
        })
    ids = [{"occurrenceId": f"{A}:2026-10-19", "role": r, "osAlarmId": os_alarm_id(f"{A}:2026-10-19", r)}
           for r in ("main", "nag1", "nag2", "nag3")]
    return {"alarm-plan/cases.json": {"osAlarmIds": ids, "cases": cases}}


VALIDATION_CASES = [
    ("valid-weekly", alarm(A, times=every_day("06:30"))),
    ("invalid-time-format", alarm(A, times={"mon": "6:30"})),
    ("invalid-hour", alarm(A, times={"mon": "24:00"})),
    ("empty-weekly", alarm(A, times={})),
    ("override-in-past", alarm(A, times=every_day("06:30"), overrides=[{"date": "2026-10-01", "time": "06:00"}])),
    ("override-duplicate", alarm(A, times=every_day("06:30"), overrides=[{"date": "2026-11-01", "time": "06:00"},
                                                                        {"date": "2026-11-01", "skip": True}])),
    ("pause-too-long", alarm(A, times=every_day("06:30"), pause={"from": "2026-11-01", "to": "2026-12-01"})),
    ("pause-30-days-ok", alarm(A, times=every_day("06:30"), pause={"from": "2026-11-01", "to": "2026-11-30"})),
    ("target-too-low", alarm(A, times=every_day("06:30"), mode={"type": "ringUntilDone", "targetReps": 4})),
    ("target-too-high", alarm(A, times=every_day("06:30"), mode={"type": "beatTheClock", "targetReps": 101, "windowSeconds": 60})),
    ("beat-the-clock-window", alarm(A, times=every_day("06:30"), mode={"type": "beatTheClock", "targetReps": 10, "windowSeconds": 20})),
    ("sprint-window-must-be-preset", alarm(A, times=every_day("06:30"), mode={"type": "sprint", "windowSeconds": 90, "minimumReps": 10})),
    ("sets-valid", alarm(A, times=every_day("06:30"), mode={"type": "sets", "sets": 3, "repsPerSet": 10, "restSeconds": 45})),
    ("sets-invalid", alarm(A, times=every_day("06:30"), mode={"type": "sets", "sets": 6, "repsPerSet": 4, "restSeconds": 10})),
    ("escalation-valid", alarm(A, times=every_day("06:30"), mode={"type": "escalation", "targetReps": 10,
                                                                  "snoozeAddsReps": 5, "snoozeMinutes": 5, "maxSnoozes": 3})),
    ("escalation-invalid", alarm(A, times=every_day("06:30"), mode={"type": "escalation", "targetReps": 10,
                                                                    "snoozeAddsReps": 0, "snoozeMinutes": 11, "maxSnoozes": 6})),
    ("unknown-mode", alarm(A, times=every_day("06:30"), mode={"type": "dance"})),
]


def build_validation_vectors() -> dict[str, dict]:
    today = date(2026, 10, 19)
    cases = [{"id": cid, "schedule": s, "expectedErrors": sorted(set(validate_schedule(s, today)))}
             for cid, s in VALIDATION_CASES]
    return {"alarm-validation/cases.json": {"today": today.isoformat(), "cases": cases}}


def build_trophy_vectors() -> dict[str, dict]:
    pairs = [(me, opp) for me in (0, 100, 599, 1000, 1999, 2500, 4000) for opp in (0, 140, 600, 1000, 1049, 1051, 2000, 3500)]
    gains = [{"me": me, "opp": opp, "winGain": ranking.win_gain(me, opp), "lossCost": ranking.loss_cost(me, opp)}
             for me, opp in pairs]

    sequences = []
    scripts = {
        "placement-then-normal": (ranking.TrophyState(0), [(0, "win"), (0, "win"), (0, "win"), (50, "loss"),
                                                            (0, "win"), (0, "win"), (100, "loss"), (100, "draw")]),
        "floor-600-holds": (ranking.TrophyState(590, placement_left=0),
                            [(590, "win"), (620, "loss"), (620, "loss"), (620, "loss")]),
        "floor-2000-and-streak": (ranking.TrophyState(1990, floor=1200, placement_left=0),
                                  [(1900, "win"), (1900, "win"), (1900, "win"), (2500, "loss"), (2600, "loss")]),
        "zero-never-negative": (ranking.TrophyState(8, placement_left=0), [(8, "loss"), (8, "loss")]),
        "underdog-streak": (ranking.TrophyState(1000, placement_left=0), [(1600, "win"), (1600, "win"), (1600, "win"), (1600, "win")]),
    }
    for name, (state, steps) in scripts.items():
        cur = state
        out_steps = []
        for opp, outcome in steps:
            cur, applied = ranking.apply_ranked_result(cur, opp, outcome)
            out_steps.append({"opp": opp, "outcome": outcome, "delta": applied, "after": cur.to_json()})
        sequences.append({"id": name, "start": state.to_json(), "steps": out_steps})

    leagues = [{"trophies": t, **ranking.league_for(t)} for t in
               (0, 199, 200, 399, 400, 599, 600, 799, 800, 999, 1000, 1199, 1200, 1465, 1466, 1731, 1732, 1999,
                2000, 2332, 2333, 2665, 2666, 2999, 3000, 3999, 4000, 4999, 5000, 12345)]
    resets = [{"before": t, "after": ranking.season_reset(t)} for t in (0, 1999, 2000, 2001, 2002, 3001, 9999)]
    wake = [{"mode": m, "finalTargetReps": r, "avgQuality": q, "snoozesUsed": s, "points": ranking.wake_points(m, r, q, s)}
            for m, r, q, s in [("ringUntilDone", 5, 60, 0), ("ringUntilDone", 20, 75, 0), ("ringUntilDone", 100, 90, 0),
                               ("beatTheClock", 10, 74, 0), ("sprint", 30, 95, 0), ("sets", 30, 89, 0),
                               ("escalation", 25, 80, 0), ("escalation", 10, 50, 1), ("escalation", 5, 50, 3),
                               ("ringUntilDone", 99, 100, 0)]]
    return {
        "trophies/win-loss-table.json": {"cases": gains},
        "trophies/sequences.json": {"sequences": sequences},
        "trophies/leagues.json": {"cases": leagues},
        "trophies/season-reset.json": {"cases": resets},
        "trophies/wake-points.json": {"cases": wake},
    }


def build_battle_vectors() -> dict[str, dict]:
    from pushly_ref import battle
    from pushly_ref.battle_cases import CASES

    cases = []
    for cid, mode, variant, a, b, winner, reason in CASES:
        got = battle.decide(mode, variant, a, b)
        assert (got["winner"], got["reason"]) == (winner, reason), (cid, got)
        cases.append({"id": cid, "mode": mode, "variant": variant, "a": a, "b": b, "expected": got})
    games = [
        ("glickman-example", 1500, 200, 0.06, [(1400, 30, 1), (1550, 100, 0), (1700, 300, 0)]),
        ("new-vs-new-win", 1500, 350, 0.06, [(1500, 350, 1)]),
        ("new-vs-new-loss", 1500, 350, 0.06, [(1500, 350, 0)]),
        ("settled-upset-win", 1400, 60, 0.06, [(1800, 50, 1)]),
        ("settled-expected-win", 1800, 50, 0.06, [(1400, 60, 1)]),
        ("draw", 1600, 120, 0.07, [(1600, 120, 0.5)]),
    ]
    mmr = []
    for gid, r, rd, vol, opps in games:
        nr, nrd, nvol = battle.glicko2(r, rd, vol, opps)
        mmr.append({"id": gid, "rating": r, "rd": rd, "vol": vol,
                    "opponents": [{"rating": o[0], "rd": o[1], "score": o[2]} for o in opps],
                    "expected": {"rating": round(nr, 6), "rd": round(nrd, 6), "vol": round(nvol, 8)}})
    return {"battles/results.json": {"cases": cases}, "battles/glicko2.json": {"cases": mmr}}


def build_ads_vectors() -> dict[str, dict]:
    from pushly_ref import ads
    from pushly_ref.ads_cases import CASES

    cases = []
    for cid, placement, ctx, allowed, reason in CASES:
        got = ads.can_show(placement, ctx)
        assert got == (allowed, reason), (cid, got)
        cases.append({"id": cid, "placement": placement, "context": ctx, "allowed": allowed, "reason": reason})
    return {"ads/gate.json": {"cases": cases}}


def build_battle_hud_vectors() -> dict[str, dict]:
    from pushly_ref import battle_hud as hud
    from pushly_ref.battle_hud_cases import BO3, CLINCHED, TURNS

    bo3 = []
    for cid, t, expected in BO3:
        assert hud.bo3_clock(t) == expected, (cid, hud.bo3_clock(t))
        bo3.append({"id": cid, "t": t, "expected": expected})
    clinched = []
    for cid, mine, theirs, expected in CLINCHED:
        assert hud.bo3_clinched(mine, theirs) == expected, cid
        clinched.append({"id": cid, "mySets": mine, "theirRaw": theirs, "expected": expected})
    turns = []
    for cid, t, my_last, their_last, expected in TURNS:
        assert hud.turn_state(t, my_last, their_last) == expected, (cid, hud.turn_state(t, my_last, their_last))
        turns.append({"id": cid, "t": t, "myLast": my_last, "theirLast": their_last, "expected": expected})
    return {"battles/hud.json": {"bo3Clock": bo3, "bo3Clinched": clinched, "turns": turns}}


def build_clan_war_vectors() -> dict[str, dict]:
    totals = [{"rawRepsDay": r, "lowTrust": lt, "counted": clan_war.counted_total(r, lt)}
              for r in (0, 1, 199, 200, 201, 202, 300, 301, 399, 400, 401, 1000) for lt in (False, True)]
    sessions = []
    for name, splits, lt in [("single-big-session", [450], False), ("many-small", [50] * 10, False),
                             ("crossing-caps", [180, 40, 190, 30], False), ("low-trust-split", [99, 101, 77], True)]:
        before, steps = 0, []
        for n in splits:
            steps.append({"repsTodayBefore": before, "newReps": n,
                          "counted": clan_war.counted_for_session(before, n, lt)})
            before += n
        sessions.append({"id": name, "lowTrust": lt, "steps": steps,
                         "dayTotalCounted": clan_war.counted_total(before, lt)})
    return {"clan-war/day-totals.json": {"cases": totals}, "clan-war/session-splits.json": {"sequences": sessions}}


def build_account_vectors() -> dict[str, dict]:
    names = ["Dan", "ab", "abc", "AnaFit", "ana.fit_99", "a" * 20, "a" * 21, "ana fit", "ana-fit", "ána", "u_0123456789ab",
             "u_0123456789AB", "U_0123456789ab", "user_123", "...", "___", "12345", "emoji🔥"]
    years = [(1899, 2026), (1900, 2026), (2010, 2026), (2011, 2026), (2009, 2026), (2026, 2026), (2027, 2026), (1990, 2026)]
    versions = [("1.0.0", "1.0.0"), ("1.0.0", "1.0.1"), ("1.2", "1.10"), ("1.10.0", "1.9.9"), ("2.0.0 (45)", "1.9.0"),
                ("0.1.0", "1.0.0"), ("1.0.0", "1")]
    return {"account/rules.json": {
        "usernames": [{"name": n, "error": account.username_error(n)} for n in names],
        "birthYears": [{"birthYear": b, "currentYear": c, "error": account.birth_year_error(b, c)} for b, c in years],
        "versions": [{"app": a, "minSupported": m, "updateRequired": account.update_required(a, m)} for a, m in versions],
    }}


PUSHUP_DIR = OUT / "pushup"


def pushup_files() -> dict[str, bytes]:
    """Synthetic RepEngine vectors (gzip JSON). `reference` = events of the reference engine (parity check)."""
    from pushly_ref import pushup_scenarios, rep_engine

    files = {}
    for sid, vector in pushup_scenarios.build().items():
        result = rep_engine.run(vector)
        vector["reference"] = {"counted": result["counted"], "rejected": result["rejected"], "events": result["events"]}
        raw = (json.dumps(vector, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
        files[f"synthetic-{sid}.json.gz"] = raw
    return files


def build_wake_vectors() -> dict[str, dict]:
    """Wake Challenge server rules (doc 04 §3/§7, doc 08 §3). Labels in wake_cases.py; the reference must agree."""
    from pushly_ref import wake, wake_cases as wc

    bad = []
    decisions = []
    for cid, mode, now, sess, expect, note in wc.DECISIONS:
        got = wake.decide(mode, wc.T0, now, sess)
        if got["status"] != expect:
            bad.append(f"decision {cid}: expected {expect}, reference says {got['status']} ({got['reason']})")
        decisions.append({"id": cid, "note": note, "mode": mode, "t0": wc.T0, "now": now, "session": sess,
                          "expected": got})
    points = []
    for cid, target, mtype, snoozes, q, expect in wc.POINTS:
        got = wake.wake_points(target, mtype, snoozes, q)
        if got != expect:
            bad.append(f"points {cid}: expected {expect}, reference says {got}")
        points.append({"id": cid, "finalTargetReps": target, "mode": mtype, "snoozesUsed": snoozes, "avgQuality": q,
                       "expectedPoints": got})
    streaks = []
    for cid, days, grants, expect in wc.STREAKS:
        got = wake.streak_fold([{"date": d, "status": st} for d, st in days],
                               [{"date": d, "count": n} for d, n in grants])
        tup = (got["current"], got["best"], got["pureCurrent"], got["pureBest"], got["freezesAvailable"])
        if tup != expect:
            bad.append(f"streak {cid}: expected {expect}, reference says {tup}")
        streaks.append({"id": cid, "days": [{"date": d, "status": st} for d, st in days],
                        "freezeGrants": [{"date": d, "count": n} for d, n in grants], "expected": got})
    plans = []
    for cid, d, tz, alarms, kind, t0, note in wc.DAY_PLANS:
        got = wake.day_plan(alarms, date.fromisoformat(d), tz).to_json()
        if got["kind"] != kind or got.get("t0") != t0:
            bad.append(f"day plan {cid}: expected {kind} {t0}, reference says {got['kind']} {got.get('t0')}")
        plans.append({"id": cid, "note": note, "localDate": d, "timeZone": tz, "alarms": alarms, "expected": got})
    if bad:
        raise SystemExit("Wake cases disagree with the reference:\n  " + "\n  ".join(bad))
    return {"wake/decisions.json": {"cases": decisions}, "wake/points.json": {"cases": points},
            "wake/streaks.json": {"cases": streaks}, "wake/day-plans.json": {"cases": plans}}


def build_rep_log_vectors() -> dict[str, dict]:
    """submit-rep-session plausibility checks + server-time conversion (doc 06 §4). Labels in rep_log_cases.py."""
    import jsonschema
    from pushly_ref import rep_log, rep_log_cases as rc

    schema = json.loads((ROOT / "shared/contracts/rep-log.schema.json").read_text())
    received = rep_log.iso_ms(rc.RECEIVED)
    bad, cases = [], []
    for cid, log, (hard, hold, soft), note in rc.CASES:
        try:
            jsonschema.validate(log, schema)
        except jsonschema.ValidationError as e:
            bad.append(f"rep log {cid}: not valid against rep-log.schema.json: {e.message}")
        got = rep_log.check(log, received)
        if (got["hard"], got["hold"], got["soft"]) != (hard, hold, soft):
            bad.append(f"rep log {cid}: expected {(hard, hold, soft)}, reference says "
                       f"{(got['hard'], got['hold'], got['soft'])}")
        cases.append({"id": cid, "note": note, "receivedAtMs": received, "log": log, "expected": got})
    if bad:
        raise SystemExit("Rep-log cases disagree with the reference:\n  " + "\n  ".join(bad))
    return {"rep-log/cases.json": {"cases": cases}}


def build_progress_vectors() -> dict[str, dict]:
    """XP → level (doc 10 §5) and achievement unlocking (doc 10 §4); labels checked by hand below."""
    from pushly_ref import progress as pg

    levels = [{"xp": xp, "expected": pg.level_progress(xp)} for xp in
              (0, 1, 99, 100, 101, 282, 283, 519, 520, 800, 1000, 5000, 20000, 100000, 10**9)]
    hand = {0: 1, 99: 1, 100: 2, 283: 3, 520: 4, 10**9: pg.MAX_LEVEL}
    bad = [f"level for {x} xp: {pg.level_for_xp(x)} != {lv}" for x, lv in hand.items() if pg.level_for_xp(x) != lv]
    cases = [
        ("brand-new", {}, [], []),
        ("first-wake", {"wakes": 1, "repsTotal": 20, "sessions": 1, "bestSet": 20, "maxDay": 20, "bestStreak": 1,
                        "level": 1}, [], ["first_wake"]),
        ("first-wake-already-had-it", {"wakes": 1}, ["first_wake"], []),
        ("big-day", {"repsTotal": 140, "maxDay": 120, "bestSet": 30, "sessions": 4},
         [], ["reps_100", "day_50", "century", "set_25"]),
        ("streaks", {"wakes": 31, "bestStreak": 30}, ["first_wake", "wake_7"],
         ["wake_30", "streak_3", "streak_7", "streak_30"]),
        ("early-bird", {"wakes": 12, "wakesBefore": {"06:00": 10}}, ["first_wake", "wake_7"], ["early_bird"]),
        ("hard-modes-add-up", {"wakes": 10, "wakesByMode": {"sprint": 4, "sets": 3, "beatTheClock": 3,
                                                            "ringUntilDone": 50}},
         ["first_wake", "wake_7"], ["hard_mode"]),
        ("form", {"sessions": 3, "bestAvgByMinReps": {"10": 96, "50": 84}}, [], ["textbook", "perfect_ten"]),
        ("form-long-set", {"sessions": 3, "bestAvgByMinReps": {"10": 88, "50": 86}}, [], ["clean_fifty"]),
        ("levels", {"level": 12}, [], ["level_5", "level_10"]),
        ("battles-not-yet", {"battleWins": 5, "friends": 9}, [], []),
    ]
    out = []
    for cid, facts, already, expect in cases:
        got = pg.unlocked(facts, already)
        if got != expect:
            bad.append(f"achievements {cid}: expected {expect}, reference says {got}")
        out.append({"id": cid, "facts": facts, "already": already, "expected": got})
    if len(pg.DEFINITIONS["definitions"]) < 40:
        bad.append("doc 10 §4: at least 40 achievements in v1")
    if bad:
        raise SystemExit("Progress cases disagree with the reference:\n  " + "\n  ".join(bad))
    return {"progress/levels.json": {"cases": levels}, "progress/achievements.json": {"cases": out}}


INTEGRITY_CASES = [
    # (id, pushup vector, transform, expect continuity > 0?, expect replay > 0?, note)
    ("clean-normal", "synthetic-good-10-normal", {}, False, False, "steady camera, real body"),
    ("clean-noisy", "synthetic-good-5-noisy", {}, False, False, "landmark noise is not replay"),
    ("feed-gaps", "synthetic-good-10-normal", {"dropEveryMs": 2000, "gapMs": 500}, True, False,
     "a 500 ms hole every 2 s — dropped / injected stream"),
    ("frozen-feed", "synthetic-good-10-normal", {"freezeAt": 120, "freezeFrames": 8}, True, False,
     "8 identical frames — frozen camera"),
    ("wobbly-limbs", "synthetic-good-10-normal", {"wobble": 0.3}, False, True,
     "forearm/upper-arm lengths swing ±30 % — flat replay on a screen"),
]


def integrity_transform(frames: list[dict], tr: dict) -> list[dict]:
    """Same transforms are implemented by the platform tests (keep in sync, they are tiny)."""
    import copy
    import math
    out = copy.deepcopy(frames)
    if "dropEveryMs" in tr:
        t0 = out[0]["t"]
        out = [f for f in out if (f["t"] - t0) % tr["dropEveryMs"] >= tr["gapMs"] or f["t"] == t0]
    if "freezeAt" in tr:
        k = tr["freezeAt"]
        for i in range(k + 1, k + tr["freezeFrames"]):
            out[i]["lm"] = copy.deepcopy(out[k]["lm"])
            out[i]["w"] = copy.deepcopy(out[k]["w"])
    if "wobble" in tr:
        for i, f in enumerate(out):
            s = 1 + tr["wobble"] * math.sin(i / 7.0)
            for j in (13, 14, 15, 16):
                f["w"][j] = [f["w"][j][0] * s, f["w"][j][1] * s, f["w"][j][2] * s]
    return out


def build_integrity_vectors() -> dict[str, dict]:
    """Session integrity signals (doc 06 §2.3–2.4) for SessionMonitor on both platforms."""
    import gzip
    from pushly_ref import integrity, rep_engine

    cases, bad = [], []
    for cid, source, tr, want_cont, want_replay, note in INTEGRITY_CASES:
        v = json.loads(gzip.decompress((PUSHUP_DIR / f"{source}.json.gz").read_bytes()))
        frames = integrity_transform(v["frames"], tr)
        engine = rep_engine.RepEngine(v["meta"]["imageWidth"], v["meta"]["imageHeight"])
        mon = integrity.SessionMonitor()
        t0 = frames[0]["t"]
        for f in frames:
            engine.process(f)
            mon.frame(f, engine.last_features, f["t"] - t0)
        got = mon.summary()
        if (got["continuity"] > 0) != want_cont or (got["replay"] > 0) != want_replay:
            bad.append(f"integrity {cid}: continuity {got['continuity']}, replay {got['replay']}")
        cases.append({"id": cid, "note": note, "source": source, "transform": tr, "expected": got})
    if bad:
        raise SystemExit("Integrity cases disagree with the reference:\n  " + "\n  ".join(bad))
    return {"integrity/cases.json": {"cases": cases}}


SQL_VALIDATION_TEST = ROOT / "supabase/tests/031_alarm_validation_vectors.sql"


def sql_validation_test() -> str:
    """pgTAP test: the server's app.alarm_validation_errors() must agree with every shared validation vector."""
    data = build_validation_vectors()["alarm-validation/cases.json"]
    lines = [
        "-- GENERATED by tools/reference/build_vectors.py from shared/test-vectors/alarm-validation — do not edit.",
        "-- The server validates alarms with exactly the same rules as the apps (doc 04 §2).",
        "begin;",
        f"select plan({len(data['cases'])});",
    ]
    for c in data["cases"]:
        js = json.dumps(c["schedule"], ensure_ascii=False).replace("'", "''")
        expected = ", ".join("'" + e + "'" for e in sorted(c["expectedErrors"]))
        lines.append(
            "select is((select coalesce(array_agg(e order by e), '{}') from unnest(app.alarm_validation_errors("
            f"'{js}'::jsonb, '{data['today']}'::date)) e), array[{expected}]::text[], '{c['id']}');"
        )
    lines += ["select * from finish();", "rollback;"]
    return "\n".join(lines) + "\n"


WAKE_SQL_TEST = ROOT / "supabase/tests/041_wake_vectors.sql"


def wake_sql_test() -> str:
    """pgTAP test: the server's wake rules (app.decide_wake, wake_points, streak_fold, day_plan_from) must agree with
    every shared wake vector."""
    v = build_wake_vectors()
    q = lambda o: "'" + json.dumps(o, ensure_ascii=False, separators=(",", ":")).replace("'", "''") + "'::jsonb"  # noqa: E731
    lines = []
    for c in v["wake/points.json"]["cases"]:
        lines.append(f"select is(app.wake_points({c['finalTargetReps']}, '{c['mode']}', {c['snoozesUsed']}, "
                     f"{c['avgQuality']}), {c['expectedPoints']}, 'points {c['id']}');")
    for c in v["wake/decisions.json"]["cases"]:
        lines.append(f"select is(app.decide_wake({q(c['mode'])}, {c['t0']}, {c['now']}, {q(c['session'])}), "
                     f"{q(c['expected'])}, 'decision {c['id']}');")
    for c in v["wake/streaks.json"]["cases"]:
        lines.append(f"select is(app.streak_fold({q(c['days'])}, {q(c['freezeGrants'])}), {q(c['expected'])}, "
                     f"'streak {c['id']}');")
    for c in v["wake/day-plans.json"]["cases"]:
        lines.append(f"select is(app.day_plan_from({q(c['alarms'])}, '{c['localDate']}'::date, '{c['timeZone']}'), "
                     f"{q(c['expected'])}, 'day plan {c['id']}');")
    head = ["-- GENERATED by tools/reference/build_vectors.py from shared/test-vectors/wake — do not edit.",
            "-- The server decides wake results with exactly the reference rules (doc 04 §3/§7, doc 08 §3).",
            "begin;", f"select plan({len(lines)});"]
    return "\n".join(head + lines + ["select * from finish();", "rollback;"]) + "\n"


BATTLE_SQL_TEST = ROOT / "supabase/tests/081_battle_vectors.sql"


def battle_sql_test() -> str:
    """pgTAP test: trophies, leagues, season reset, Glicko-2 and battle results in SQL match the shared vectors."""
    t = build_trophy_vectors()
    v = build_battle_vectors()
    q = lambda o: "'" + json.dumps(o, ensure_ascii=False, separators=(",", ":")).replace("'", "''") + "'::jsonb"  # noqa: E731
    lines = []
    for c in t["trophies/win-loss-table.json"]["cases"]:
        lines.append(f"select is(array[app.win_gain({c['me']}, {c['opp']}), app.loss_cost({c['me']}, {c['opp']})], "
                     f"array[{c['winGain']}, {c['lossCost']}], 'gain/cost {c['me']} vs {c['opp']}');")
    for seq in t["trophies/sequences.json"]["sequences"]:
        state = seq["start"]
        for k, step in enumerate(seq["steps"]):
            want = dict(step["after"], delta=step["delta"])
            lines.append(f"select is(app.apply_ranked({q(state)}, {step['opp']}, '{step['outcome']}'), {q(want)}, "
                         f"'trophies {seq['id']} step {k + 1}');")
            state = step["after"]
    for c in t["trophies/leagues.json"]["cases"]:
        lines.append(f"select is(app.league_for({c['trophies']}), {q({'league': c['league'], 'tier': c['tier']})}, "
                     f"'league {c['trophies']}');")
    for c in t["trophies/season-reset.json"]["cases"]:
        lines.append(f"select is(app.season_reset({c['before']}), {c['after']}, 'season reset {c['before']}');")
    for c in v["battles/glicko2.json"]["cases"]:
        opps = [{"rating": o["rating"], "rd": o["rd"], "score": o["score"]} for o in c["opponents"]]
        lines.append(f"select is((select jsonb_build_object('rating', round((g->>'rating')::numeric, 6), "
                     f"'rd', round((g->>'rd')::numeric, 6), 'vol', round((g->>'vol')::numeric, 8)) "
                     f"from app.glicko2({c['rating']}, {c['rd']}, {c['vol']}, {q(opps)}) g), {q(c['expected'])}, "
                     f"'glicko2 {c['id']}');")
    for c in v["battles/results.json"]["cases"]:
        lines.append(f"select is(app.decide_battle('{c['mode']}', {q(c['variant'])}, {q(c['a'])}, {q(c['b'])}), "
                     f"{q(c['expected'])}, 'battle {c['id']}');")
    head = ["-- GENERATED by tools/reference/build_vectors.py from shared/test-vectors/{trophies,battles} — do not edit.",
            "-- Trophy, league, MMR and battle-result math on the server is exactly the reference (doc 07, doc 08).",
            "begin;", f"select plan({len(lines)});"]
    return "\n".join(head + lines + ["select * from finish();", "rollback;"]) + "\n"


CLAN_WAR_SQL_TEST = ROOT / "supabase/tests/091_clan_war_vectors.sql"


def clan_war_sql_test() -> str:
    """pgTAP test: Clan War rep counting in SQL matches shared/test-vectors/clan-war."""
    v = build_clan_war_vectors()
    lines = []
    for c in v["clan-war/day-totals.json"]["cases"]:
        lines.append(f"select is(app.clan_war_day_total({c['rawRepsDay']}, {str(c['lowTrust']).lower()}), {c['counted']}, "
                     f"'day total {c['rawRepsDay']} low={c['lowTrust']}');")
    for seq in v["clan-war/session-splits.json"]["sequences"]:
        for k, st in enumerate(seq["steps"]):
            lines.append(f"select is(app.clan_war_count({st['repsTodayBefore']}, {st['newReps']}, {str(seq['lowTrust']).lower()}), "
                         f"{st['counted']}, 'split {seq['id']} step {k + 1}');")
    head = ["-- GENERATED by tools/reference/build_vectors.py from shared/test-vectors/clan-war — do not edit.",
            "-- Clan War caps on the server are exactly the reference (doc 09 §3).",
            "begin;", f"select plan({len(lines)});"]
    return "\n".join(head + lines + ["select * from finish();", "rollback;"]) + "\n"


PROGRESS_SQL_TEST = ROOT / "supabase/tests/061_progress_vectors.sql"


def progress_sql_test() -> str:
    """pgTAP test: levels and achievement rules in SQL match the shared progress vectors, and the seeded
    achievement_definitions table matches shared/achievements/definitions.json."""
    v = build_progress_vectors()
    q = lambda o: "'" + json.dumps(o, ensure_ascii=False, separators=(",", ":")).replace("'", "''") + "'::jsonb"  # noqa: E731
    arr = lambda xs: "array[" + ",".join("'" + x + "'" for x in xs) + "]::text[]"  # noqa: E731
    lines = []
    for c in v["progress/levels.json"]["cases"]:
        lines.append(f"select is(app.level_progress({c['xp']}), {q(c['expected'])}, 'level xp={c['xp']}');")
    for c in v["progress/achievements.json"]["cases"]:
        lines.append(f"select is(app.achievements_unlocked({q(c['facts'])}, {arr(c['already'])}), "
                     f"{arr(c['expected'])}, 'achievements {c['id']}');")
    defs = json.loads((ROOT / "shared/achievements/definitions.json").read_text())["definitions"]
    want = [{"id": d["id"], "group": d["group"], "title": d["title"], "description": d["description"],
             "icon": d["icon"], "tier": d["tier"], "rule": d["rule"], "xp": d["xp"],
             "streakFreezes": d["streakFreezes"]} for d in defs]
    lines.append("select is((select jsonb_agg(jsonb_build_object('id', id, 'group', group_name, 'title', title, "
                 "'description', description, 'icon', icon, 'tier', tier, 'rule', rule, 'xp', xp, "
                 "'streakFreezes', streak_freezes) order by sort) from public.achievement_definitions where active), "
                 f"{q(want)}, 'achievement_definitions match shared/achievements/definitions.json');")
    head = ["-- GENERATED by tools/reference/build_vectors.py from shared/test-vectors/progress — do not edit.",
            "-- XP levels and achievement rules on the server are exactly the reference rules (doc 10 §4-5).",
            "begin;", f"select plan({len(lines)});"]
    return "\n".join(head + lines + ["select * from finish();", "rollback;"]) + "\n"


def build_workout_vectors() -> dict[str, dict]:
    from pushly_ref import workout as wk
    from pushly_ref.workout_cases import RUNNER, VALIDATION

    presets = json.loads((ROOT / "shared/workouts/presets.json").read_text())["presets"]
    for p in presets:
        assert wk.validate(p) == [], (p["id"], wk.validate(p))
    runner = []
    for cid, w, steps, t_end in RUNNER:
        r = wk.run(w, steps)
        runner.append({"id": cid, "workout": w, "steps": steps, "events": r.events, "results": r.results,
                       "final": r.snapshot(t_end), "finalT": t_end})
    validation = [{"id": cid, "workout": w, "expectedErrors": wk.validate(w)} for cid, w, exp in VALIDATION]
    for (cid, _, exp), v in zip(VALIDATION, validation):
        assert v["expectedErrors"] == exp, (cid, v["expectedErrors"])
    planned = [{"id": p["id"], "planned": wk.planned_reps(p)} for p in presets]
    return {"workouts/runner.json": {"amrapIdleMs": wk.AMRAP_IDLE_MS, "runner": runner, "validation": validation,
                                     "plannedReps": planned}}


def all_files() -> dict[str, str]:
    files: dict[str, dict] = {}
    for builder in (build_occurrence_vectors, build_plan_vectors, build_validation_vectors, build_trophy_vectors, build_clan_war_vectors,
                    build_account_vectors, build_wake_vectors, build_rep_log_vectors,
                    build_integrity_vectors, build_progress_vectors, build_battle_vectors,
                    build_ads_vectors, build_battle_hud_vectors, build_workout_vectors):
        files.update(builder())
    return {path: json.dumps(content, indent=2, ensure_ascii=False) + "\n" for path, content in files.items()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    files = all_files()
    bad = []
    import gzip

    for name, raw in pushup_files().items():
        path = PUSHUP_DIR / name
        if args.check:
            if not path.exists() or gzip.decompress(path.read_bytes()) != raw:
                bad.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(gzip.compress(raw, compresslevel=9, mtime=0))
    # Real recordings (tools/pose-recorder/import.py): the reference block must match the current engine.
    sys.path.insert(0, str(ROOT / "tools/pose-recorder"))
    from importlib import import_module

    finish = import_module("import").finish
    for path in sorted(PUSHUP_DIR.glob("real-*.json.gz")):
        current = gzip.decompress(path.read_bytes())
        fresh = finish(json.loads(current))
        if args.check:
            if current != fresh:
                bad.append(str(path.relative_to(ROOT)))
        elif current != fresh:
            path.write_bytes(gzip.compress(fresh, compresslevel=9, mtime=0))
    if args.check:
        known = set(pushup_files())
        bad += [f"(stale extra file) {p.name}" for p in PUSHUP_DIR.glob("synthetic-*.json.gz") if p.name not in known]
    for target, content in ((WAKE_SQL_TEST, wake_sql_test()), (PROGRESS_SQL_TEST, progress_sql_test()),
                            (BATTLE_SQL_TEST, battle_sql_test()),
                            (CLAN_WAR_SQL_TEST, clan_war_sql_test())):
        if args.check:
            if not target.exists() or target.read_text() != content:
                bad.append(str(target.relative_to(ROOT)))
        else:
            target.write_text(content)
    sql = sql_validation_test()
    if args.check:
        if not SQL_VALIDATION_TEST.exists() or SQL_VALIDATION_TEST.read_text() != sql:
            bad.append(str(SQL_VALIDATION_TEST.relative_to(ROOT)))
    else:
        SQL_VALIDATION_TEST.write_text(sql)
    for rel, content in files.items():
        path = OUT / rel
        if args.check:
            if not path.exists() or path.read_text() != content:
                bad.append(rel)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if args.check:
        managed_dirs = {OUT / Path(r).parent for r in files}
        extra = [str(p.relative_to(OUT)) for d in managed_dirs for p in d.glob("*.json") if str(p.relative_to(OUT)) not in files]
        bad += [f"(stale extra file) {e}" for e in extra]
        if bad:
            print("Test vectors differ from the reference:", *bad, sep="\n  ")
            return 1
        print(f"test vectors up to date ({len(files)} files)")
    else:
        print(f"wrote {len(files)} vector files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
