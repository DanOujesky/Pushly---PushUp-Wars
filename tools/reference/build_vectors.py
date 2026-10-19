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


def all_files() -> dict[str, str]:
    files: dict[str, dict] = {}
    for builder in (build_occurrence_vectors, build_validation_vectors, build_trophy_vectors, build_clan_war_vectors,
                    build_account_vectors):
        files.update(builder())
    return {path: json.dumps(content, indent=2, ensure_ascii=False) + "\n" for path, content in files.items()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    files = all_files()
    bad = []
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
