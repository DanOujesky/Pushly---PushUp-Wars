"""Hand-labelled Wake Challenge cases (doc 04 §3/§7, doc 08 §3). `expect` is what a human reading the docs says the
answer is; build_vectors.py fails if the reference (wake.py) disagrees, so the vectors can't drift silently.

Times: T0 = 2026-10-20T05:00:00Z (07:00 in Prague). Rep times are epoch ms in server time.
"""
from __future__ import annotations

from datetime import datetime, timezone

T0 = int(datetime(2026, 10, 20, 5, 0, tzinfo=timezone.utc).timestamp() * 1000)
S, MIN = 1000, 60_000

A = "a0000000-0000-4000-8000-000000000001"
B = "b0000000-0000-4000-8000-000000000002"
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def reps(n: int, start: int, every: int = 2 * S, dur: int = 1500, quality: int = 80) -> list[dict]:
    return [{"tStart": start + i * every, "tEnd": start + i * every + dur, "quality": quality} for i in range(n)]


def session(rep_list, start=None, end=None, ring=T0, outcome="completed", **extra) -> dict:
    start = start if start is not None else (rep_list[0]["tStart"] - 10 * S if rep_list else T0 + MIN)
    end = end if end is not None else (rep_list[-1]["tEnd"] + 2 * S if rep_list else start + MIN)
    return {"startedAt": start, "endedAt": end, "ringAt": ring, "outcome": outcome, "snoozes": 0, "reps": rep_list,
            **extra}


RUD = {"type": "ringUntilDone", "targetReps": 20}
BTC = {"type": "beatTheClock", "targetReps": 10, "windowSeconds": 60}
SPRINT = {"type": "sprint", "windowSeconds": 60, "minimumReps": 15}
SETS = {"type": "sets", "sets": 3, "repsPerSet": 10, "restSeconds": 60}
ESC = {"type": "escalation", "targetReps": 10, "snoozeAddsReps": 5, "snoozeMinutes": 5, "maxSnoozes": 3}

_set = lambda i, start: (reps(10, start), {"start": start - 2 * S, "end": start + 10 * 2 * S})  # noqa: E731


def _sets(starts):
    rs, ss = [], []
    for st in starts:
        r, s = _set(0, st)
        rs += r
        ss.append(s)
    return rs, ss


_ok_sets = _sets([T0 + 1 * MIN, T0 + 2 * MIN + 20 * S, T0 + 3 * MIN + 40 * S])
_late_set = _sets([T0 + 1 * MIN, T0 + 3 * MIN + 30 * S])      # rest 2:10 after set 1 ends → > 60 + 30 s
_short_set = (reps(10, T0 + MIN) + reps(7, T0 + 2 * MIN + 20 * S) + reps(10, T0 + 3 * MIN + 40 * S), _ok_sets[1])

# (id, mode, now, session, expect status, note)
DECISIONS = [
    ("rud-success", RUD, T0 + 10 * MIN, session(reps(20, T0 + 2 * MIN)), "succeeded", "20 reps 2 min after the ring"),
    ("rud-extra-reps-ok", RUD, T0 + 10 * MIN, session(reps(35, T0 + 2 * MIN)), "succeeded", "more than the target"),
    ("rud-short-still-open", RUD, T0 + 10 * MIN, session(reps(12, T0 + 2 * MIN)), "in_progress",
     "12/20 and the deadline hasn't passed — the user may start another session"),
    ("rud-short-gave-up", RUD, T0 + 10 * MIN, session(reps(12, T0 + 2 * MIN), outcome="gaveUp"), "failed", "gave up"),
    ("rud-short-after-deadline", RUD, T0 + 31 * MIN, session(reps(12, T0 + 2 * MIN)), "failed",
     "deadline passed without the target"),
    ("rud-reps-after-deadline-dont-count", RUD, T0 + 40 * MIN,
     session(reps(10, T0 + 25 * MIN) + reps(10, T0 + 30 * MIN + 30 * S)), "failed", "only 10 reps before T0+30 min"),
    ("rud-reps-before-ring-dont-count", RUD, T0 + 10 * MIN,
     session(reps(20, T0 - 5 * MIN), start=T0 - 6 * MIN), "in_progress", "push-ups before the alarm don't count"),
    ("rud-clock-skew-tolerated", RUD, T0 + 10 * MIN, session(reps(20, T0 - 20 * S), start=T0 - 25 * S), "succeeded",
     "first rep 20 s 'before' the ring is within the 30 s clock tolerance"),
    ("rud-started-after-deadline", RUD, T0 + 40 * MIN, session(reps(20, T0 + 32 * MIN)), "missed",
     "session started after the deadline = missed"),
    ("btc-success", BTC, T0 + 5 * MIN, session(reps(10, T0 + 20 * S, every=3 * S)), "succeeded",
     "10th rep at T0+48.5 s, window 60 s"),
    ("btc-too-slow", BTC, T0 + 5 * MIN, session(reps(10, T0 + 40 * S, every=3 * S)), "failed",
     "10th rep at T0+68.5 s — window from T0 expired"),
    ("btc-late-ring-shifts-window", BTC, T0 + 5 * MIN, session(reps(10, T0 + 40 * S, every=3 * S), ring=T0 + 30 * S),
     "succeeded", "OS rang 30 s late (ring timestamp) → window starts at the ring"),
    ("btc-not-yet", BTC, T0 + 30 * S, session(reps(5, T0 + 10 * S, every=3 * S), end=T0 + 30 * S), "in_progress",
     "half way, window still open"),
    ("sprint-success", SPRINT, T0 + 5 * MIN, session(reps(18, T0 + 1 * MIN + 2 * S, every=3 * S), sprintStart=T0 + MIN),
     "succeeded", "18 reps in the 60 s sprint, minimum 15"),
    ("sprint-too-few", SPRINT, T0 + 5 * MIN,
     session(reps(12, T0 + MIN + 2 * S, every=4 * S), sprintStart=T0 + MIN), "failed", "12 < 15 when the window closed"),
    ("sprint-reps-outside-window", SPRINT, T0 + 5 * MIN,
     session(reps(10, T0 + MIN + 2 * S, every=3 * S) + reps(10, T0 + 2 * MIN + 10 * S), sprintStart=T0 + MIN),
     "failed", "reps after the 60 s window don't count"),
    ("sprint-not-started", SPRINT, T0 + 5 * MIN, session([], start=T0 + MIN), "in_progress",
     "camera open but the sprint countdown never started"),
    ("sprint-started-after-deadline", SPRINT, T0 + 35 * MIN,
     session(reps(20, T0 + 31 * MIN, every=2 * S), start=T0 + 29 * MIN, sprintStart=T0 + 31 * MIN), "failed",
     "session began in time but the sprint started after the deadline"),
    ("sets-success", SETS, T0 + 10 * MIN, session(_ok_sets[0], sets=_ok_sets[1]), "succeeded", "3 × 10 with 60 s rest"),
    ("sets-rest-too-long", SETS, T0 + 10 * MIN, session(_late_set[0], sets=_late_set[1]), "failed",
     "second set started 2:10 after the first ended (> rest 60 s + 30 s)"),
    ("sets-short-set-open", SETS, T0 + 10 * MIN, session(_short_set[0], sets=_short_set[1]), "in_progress",
     "set 2 had only 7 reps — not done, deadline open"),
    ("sets-short-set-gave-up", SETS, T0 + 10 * MIN, session(_short_set[0], sets=_short_set[1], outcome="gaveUp"),
     "failed", "gave up after a short set"),
    ("esc-no-snooze", ESC, T0 + 10 * MIN, session(reps(10, T0 + MIN)), "succeeded", "no snooze: target 10"),
    ("esc-two-snoozes-short", ESC, T0 + 20 * MIN, session(reps(15, T0 + 11 * MIN), snoozes=2), "in_progress",
     "2 snoozes → target 20, only 15 so far"),
    ("esc-two-snoozes-done", ESC, T0 + 20 * MIN, session(reps(20, T0 + 11 * MIN), snoozes=2), "succeeded",
     "2 snoozes → target 20 reached"),
    ("esc-snoozes-capped", ESC, T0 + 25 * MIN, session(reps(25, T0 + 16 * MIN), snoozes=9), "succeeded",
     "a client claiming 9 snoozes is capped at maxSnoozes 3 → target 25"),
]

# (id, finalTarget, mode, snoozes, avgQuality, expected points)
POINTS = [
    ("rud-20-q80", 20, "ringUntilDone", 0, 80, 15),
    ("rud-20-q95", 20, "ringUntilDone", 0, 95, 17),
    ("rud-20-q60", 20, "ringUntilDone", 0, 60, 14),
    ("rud-5-q50", 5, "ringUntilDone", 0, 50, 11),
    ("rud-200-capped", 200, "ringUntilDone", 0, 50, 30),
    ("btc-10-q75", 10, "beatTheClock", 0, 75, 16),
    ("sprint-15-q90", 15, "sprint", 0, 90, 19),
    ("sets-30-q80", 30, "sets", 0, 80, 20),
    ("esc-25-3-snoozes", 25, "escalation", 3, 70, 9),
    ("esc-10-0-snoozes", 10, "escalation", 0, 70, 12),
    ("esc-floor-5", 5, "escalation", 3, 0, 5),
    ("rud-1-q0", 1, "ringUntilDone", 0, 0, 10),
]

_d = lambda n: f"2026-10-{n:02d}"  # noqa: E731

# (id, days [(day, status)], grants [(day, count)], expected (current, best, pure, pureBest, freezes))
STREAKS = [
    ("five-in-a-row", [(_d(i), "succeeded") for i in range(1, 6)], [], (5, 5, 5, 5, 0)),
    ("miss-resets", [(_d(1), "succeeded"), (_d(2), "succeeded"), (_d(3), "missed"), (_d(4), "succeeded")], [],
     (1, 2, 1, 2, 0)),
    ("failed-resets", [(_d(1), "succeeded"), (_d(2), "failed")], [], (0, 1, 0, 1, 0)),
    ("freeze-saves-personal-not-pure", [(_d(1), "succeeded"), (_d(2), "succeeded"), (_d(3), "missed"),
                                        (_d(4), "succeeded")], [(_d(1), 1)], (3, 3, 1, 2, 0)),
    ("freezes-capped-at-two", [(_d(5), "missed"), (_d(6), "missed"), (_d(7), "missed")],
     [(_d(1), 1), (_d(2), 1), (_d(3), 1)], (0, 0, 0, 0, 0)),
    ("skip-and-void-are-neutral", [(_d(1), "succeeded"), (_d(2), "skipped"), (_d(3), "void"), (_d(4), "succeeded")],
     [], (2, 2, 2, 2, 0)),
    ("days-without-alarm-are-neutral", [(_d(1), "succeeded"), (_d(5), "succeeded")], [], (2, 2, 2, 2, 0)),
    ("undecided-ignored", [(_d(1), "succeeded"), (_d(2), "in_progress")], [], (1, 1, 1, 1, 0)),
    ("pause-within-limit", [(_d(1), "succeeded")] + [(_d(i), "paused") for i in range(2, 16)] + [(_d(16), "succeeded")],
     [], (2, 2, 2, 2, 0)),
    ("pause-over-limit-resets", [(_d(1), "succeeded")] + [(_d(i), "paused") for i in range(2, 17)]
     + [(_d(17), "succeeded")], [], (1, 1, 1, 1, 0)),
    ("pause-limit-is-per-month", [("2026-09-20", "succeeded")] + [(f"2026-09-{i}", "paused") for i in range(21, 31)]
     + [(_d(i), "paused") for i in range(1, 11)] + [(_d(11), "succeeded")], [], (2, 2, 2, 2, 0)),
    ("unordered-input", [(_d(3), "succeeded"), (_d(1), "succeeded"), (_d(2), "succeeded")], [], (3, 3, 3, 3, 0)),
]


def _alarm(id_, times=None, *, counts=True, enabled=True, overrides=(), pause=None, mode=None):
    return {"id": id_, "version": 1, "label": "Wake up", "enabled": enabled, "countsForChallenge": counts,
            "kind": "weekly", "weekly": {d: (times or {}).get(d) for d in DAYS}, "overrides": list(overrides),
            "pause": pause, "mode": mode or RUD, "sound": {"id": "bundled.rooster_rush"}}


def _every(t):
    return {d: t for d in DAYS}


def _v(n, valid_from, data):
    return {"version": n, "validFrom": valid_from, "data": data}


OLD = "2026-10-01T00:00:00Z"
# (id, date, tz, alarms {id: [versions]}, expected kind, expected t0 | None, note)
DAY_PLANS = [
    ("single-alarm", "2026-10-20", "Europe/Prague", {A: [_v(1, OLD, _alarm(A, _every("07:00")))]}, "ring",
     "2026-10-20T05:00:00Z", "07:00 Prague = 05:00 UTC"),
    ("edit-to-earlier-time-too-late", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"))), _v(2, "2026-10-20T04:44:00Z", _alarm(A, _every("06:30")))]},
     "ring", "2026-10-20T04:30:00Z",
     "at 06:44 the alarm is moved to 06:30 (already past): v2 locks the day at once → 06:30 (missed unless done) —"
     " moving an alarm can never dodge a challenge"),
    ("edit-long-before-applies", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"))), _v(2, "2026-10-19T20:00:00Z", _alarm(A, _every("06:30")))]},
     "ring", "2026-10-20T04:30:00Z", "edited the evening before → new time counts"),
    ("edit-10-min-before-ignored", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"))), _v(2, "2026-10-20T04:50:00Z", _alarm(A, _every("08:00")))]},
     "ring", "2026-10-20T05:00:00Z", "moving the alarm later 10 min before it rings doesn't change today (PS-26)"),
    ("disable-5-min-before-ignored", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"))), _v(2, "2026-10-20T04:55:00Z", _alarm(A, _every("07:00"),
                                                                                    enabled=False))]},
     "ring", "2026-10-20T05:00:00Z", "turning the alarm off at the last minute still counts as a challenge"),
    ("skip-day-before", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"), overrides=[{"date": "2026-10-20", "skip": True}]))]},
     "skipped", None, "Skip next, set in advance"),
    ("paused", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"), pause={"from": "2026-10-18", "to": "2026-10-25"}))]},
     "paused", None, "vacation mode"),
    ("practice-alarm-only", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"), counts=False))]}, "none", None, "practice alarms never count"),
    ("no-alarm-that-weekday", "2026-10-20", "Europe/Prague", {A: [_v(1, OLD, _alarm(A, {"mon": "07:00"}))]}, "none",
     None, "2026-10-20 is a Tuesday"),
    ("earliest-of-two", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:30")))], B: [_v(1, OLD, _alarm(B, _every("06:45")))]}, "ring",
     "2026-10-20T04:45:00Z", "earliest challenge alarm wins"),
    ("skip-moves-to-other-alarm", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("06:00"), overrides=[{"date": "2026-10-20", "skip": True}]))],
      B: [_v(1, OLD, _alarm(B, _every("07:30")))]}, "ring", "2026-10-20T05:30:00Z",
     "skipped 06:00 → the 07:30 alarm is today's challenge"),
    ("deleted-long-ago", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"))), _v(2, "2026-10-10T00:00:00Z", None)]}, "none", None,
     "deleted alarm"),
    ("created-10-min-before", "2026-10-20", "Europe/Prague",
     {A: [_v(1, "2026-10-20T04:50:00Z", _alarm(A, _every("07:00")))]}, "ring", "2026-10-20T05:00:00Z",
     "a challenge alarm created 10 min before it rings locks at once and counts"),
    ("deleted-5-min-before-still-counts", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, _every("07:00"))), _v(2, "2026-10-20T04:55:00Z", None)]}, "ring",
     "2026-10-20T05:00:00Z", "deleting the alarm at the last minute doesn't cancel today's challenge"),
    ("weekday-added-same-morning", "2026-10-20", "Europe/Prague",
     {A: [_v(1, OLD, _alarm(A, {"mon": "07:00"})), _v(2, "2026-10-20T04:00:00Z", _alarm(A, _every("07:00")))]},
     "none", None, "Tuesday had no ring at midnight, so the day locked as 'no challenge' before the edit"),
    ("prague-fall-back-0230", "2026-10-25", "Europe/Prague", {A: [_v(1, OLD, _alarm(A, _every("02:30")))]}, "ring",
     "2026-10-25T00:30:00Z", "DST overlap: first 02:30 (CEST)"),
    ("prague-spring-gap-0230", "2027-03-28", "Europe/Prague", {A: [_v(1, OLD, _alarm(A, _every("02:30")))]}, "ring",
     "2027-03-28T01:00:00Z", "DST gap: rings at 03:00 CEST"),
    ("new-york", "2026-10-20", "America/New_York", {A: [_v(1, OLD, _alarm(A, _every("06:00")))]}, "ring",
     "2026-10-20T10:00:00Z", "UTC−4"),
    ("kolkata", "2026-10-20", "Asia/Kolkata", {A: [_v(1, OLD, _alarm(A, _every("06:00")))]}, "ring",
     "2026-10-20T00:30:00Z", "UTC+5:30"),
]
