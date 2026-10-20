"""Hand-labelled rep-log plausibility cases (doc 06 §4). `expect` = (hard, hold, soft) a human expects; the builder
fails if rep_log.check disagrees. Every log is also validated against shared/contracts/rep-log.schema.json."""
from __future__ import annotations

import copy

RECEIVED = "2026-10-20T05:10:00Z"
SID = "f0000000-0000-4000-8000-0000000000{:02d}"


def rep_list(n, start=2000, every=2000, dur=1500, quality=85):
    return [{"i": k + 1, "tStartMs": start + k * every, "tBottomMs": start + k * every + dur // 2,
             "tEndMs": start + k * every + dur, "quality": quality} for k in range(n)]


def log(n_id, reps, *, duration=None, anchor=True, **extra):
    duration = duration if duration is not None else (reps[-1]["tEndMs"] + 2000 if reps else 10_000)
    out = {
        "sessionId": SID.format(n_id),
        "deviceId": None,
        "context": {"type": "wake", "occurrenceId": "a0000000-0000-4000-8000-000000000001:2026-10-20"},
        "specVersion": 1, "appVersion": "0.1.0 (1)", "platform": "ios", "deviceModel": "iPhone17,1",
        "timing": {"monotonicStartMs": 500_000, "monotonicEndMs": 500_000 + duration,
                   "wallStart": "2026-10-20T05:02:03Z",
                   "serverAnchor": {"serverTime": "2026-10-20T04:59:00Z", "monotonicAtAnchorMs": 380_000}
                   if anchor else None,
                   "ringStartedAtMonotonicMs": 440_000},
        "outcome": "completed", "snoozes": 0, "sprintStartMs": None, "sets": [],
        "reps": reps, "rejected": {"NOT_DEEP_ENOUGH": 1},
        "featureTrace": None, "suspicion": {"replay": 0.02, "motion": 0.01, "continuity": 0.0, "liveness": "n/a"},
        "integrity": None, "signature": None,
    }
    out.update(extra)
    return out


def _mut(base, fn):
    b = copy.deepcopy(base)
    fn(b)
    return b


_ok = log(1, rep_list(20))
_fast3 = rep_list(10)
for k in (3, 4, 5):
    _fast3[k]["tEndMs"] = _fast3[k]["tStartMs"] + 550
    _fast3[k]["tBottomMs"] = _fast3[k]["tStartMs"] + 270

def _two_sets():
    first = rep_list(100)
    second = rep_list(100, start=first[-1]["tEndMs"] + 30_000)
    for k, r in enumerate(second):
        r["i"] = 101 + k
    return log(12, first + second)



# (id, log, expected (hard, hold, soft), note)
CASES = [
    ("clean-anchored", _ok, ([], [], []), "20 normal reps, server anchor"),
    ("clean-unanchored", log(2, rep_list(20), anchor=False), ([], [], []), "offline: wall clock used"),
    ("spec-version", _mut(_ok, lambda b: b.update(specVersion=9)), (["spec_version_unsupported"], [], []),
     "unknown rule version"),
    ("index-gap", _mut(_ok, lambda b: b["reps"][5].update(i=99)), (["reps_not_sequential"], [], []),
     "rep numbers must be 1..n"),
    ("overlapping-reps", _mut(_ok, lambda b: b["reps"][6].update(tStartMs=b["reps"][5]["tEndMs"] - 500)),
     (["reps_not_sequential"], [], []), "a rep starts before the previous ended"),
    ("rep-too-short", _mut(_ok, lambda b: b["reps"][3].update(tEndMs=b["reps"][3]["tStartMs"] + 300,
                                                               tBottomMs=b["reps"][3]["tStartMs"] + 150)),
     (["rep_duration"], [], []), "a 300 ms rep is impossible (min 450 ms)"),
    ("rep-too-long", log(5, rep_list(3, every=10_000, dur=9000)), (["rep_duration"], [], []), "9 s rep"),
    ("three-fast-reps", log(6, _fast3), ([], [], ["fast_reps"]), "3 consecutive reps under 600 ms → soft flag"),
    ("machine-gun", log(7, rep_list(30, every=600, dur=500)), (["rate_sustained"], [], ["fast_reps"]),
     "1.67 reps/s for 30 reps — no human sustains that"),
    ("fast-but-human", log(8, rep_list(30, every=700, dur=650)), ([], [], []),
     "1.43 reps/s with 650 ms reps is fast but plausible"),
    ("rep-after-session-end", log(9, rep_list(20), duration=20_000), (["reps_outside_session"], [], []),
     "reps after the session ended"),
    ("clock-in-future",
     _mut(log(10, rep_list(20), anchor=False), lambda b: b["timing"].update(wallStart="2026-10-20T06:00:00Z")),
     (["clock_in_future"], [], []), "offline wall clock says the session ended 50 min after we received it"),
    ("long-set-held", log(11, rep_list(160, every=1300, dur=1200)), ([], ["long_set"], []),
     "160 reps without a break → held for review"),
    ("two-sets-of-100", _two_sets(), ([], [], []), "200 reps but a 30 s break in the middle — no hold"),
    ("replay-suspicion", _mut(_ok, lambda b: b["suspicion"].update(replay=0.8)), ([], [], ["suspicion_replay"]),
     "screen replay heuristics high"),
    ("motion-suspicion", _mut(_ok, lambda b: b["suspicion"].update(motion=0.7)), ([], [], ["suspicion_motion"]),
     "phone moved a lot"),
    ("bad-sets", _mut(_ok, lambda b: b.update(sets=[{"startMs": 5000, "endMs": 1000}])), (["sets_invalid"], [], []),
     "set ends before it starts"),
    ("empty-session", log(15, []), ([], [], []), "camera opened, no reps — valid, just zero"),
]

