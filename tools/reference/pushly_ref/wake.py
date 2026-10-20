"""Reference Wake Challenge rules (doc 04 §3 + §7, doc 08 §3) — the executable spec of what the SERVER decides.

The server (supabase/migrations/*_wake.sql) implements exactly this and is tested against the vectors generated
from it (shared/test-vectors/wake-*). The apps only show a provisional result with the same rules.

Pieces
- `day_plan`      which occurrence counts for a user's local date, using each alarm's schedule as it was 15 min before
                  the nominal ring time (the snapshot rule, PS-26) → ring / paused / skipped / none.
- `decide`        one camera session (times already converted to server time, epoch ms) against the day's mode →
                  succeeded / in_progress / failed + final target + score.
- `wake_points`   Wake Score of a succeeded attempt.
- `streak_fold`   personal + pure streak from the ordered list of decided days (+ streak-freeze grants).
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from .occurrences import local_time_for_date, parse_hhmm, resolve_local

SNAPSHOT_MINUTES = 15            # doc 04 §7
DEADLINE_MINUTES = 30            # doc 04 §3
CLOCK_TOLERANCE_MS = 30_000      # reps may start at most this long before the ring (clock skew)
SET_START_GRACE_S = 30           # sets mode: next set must start within rest + 30 s
MAX_PAUSED_DAYS_PER_MONTH = 14   # doc 04 §2 validation table
MAX_FREEZES = 2


# ---------------------------------------------------------------------------------------------------------------
# Day plan (schedule snapshot)
# ---------------------------------------------------------------------------------------------------------------
def nominal_time(schedule: dict, d: date):
    """Wall-clock time the alarm would ring on d ignoring enabled/pause/skip — used only to pick the snapshot."""
    if schedule.get("kind") == "oneOff":
        one = datetime.fromisoformat(schedule["oneOff"])
        return one.time() if one.date() == d else None
    for ov in schedule.get("overrides", []):
        if ov["date"] == d.isoformat() and not ov.get("skip") and ov.get("time"):
            return parse_hhmm(ov["time"])
    value = schedule.get("weekly", {}).get(["mon", "tue", "wed", "thu", "fri", "sat", "sun"][d.weekday()])
    return parse_hhmm(value) if value else None


def snapshot(versions: list[dict], d: date, tz: ZoneInfo) -> dict | None:
    """The version of one alarm that applies to local date d (PS-26: edits within 15 min of the ring don't change
    that day). Walking the version timeline forward, a version "locks" the day at
    max(its validFrom, its own nominal ring time on d − 15 min) if it is still the current version then; the first
    lock wins. A version without a ring that day (deleted, weekday off) uses local midnight as its ring time.
    versions: [{version, validFrom, data|None}] in any order. Returns the locking version or None."""
    ordered = sorted(versions, key=lambda x: x["validFrom"])
    for i, v in enumerate(ordered):
        start = parse_utc(v["validFrom"])
        end = parse_utc(ordered[i + 1]["validFrom"]) if i + 1 < len(ordered) else None
        data = v["data"]
        t = nominal_time(data, d) if data else None
        anchor = resolve_local(d, t if t else parse_hhmm("00:00"), tz)
        lock = max(start, anchor - timedelta(minutes=SNAPSHOT_MINUTES))
        if end is None or lock < end:
            return v
    return None


def parse_utc(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


@dataclass(frozen=True)
class DayPlan:
    kind: str                     # ring | paused | skipped | none
    alarm_id: str | None = None
    version: int | None = None
    t0: datetime | None = None    # UTC
    mode: dict | None = None
    t0_local_date: str = ""

    @property
    def deadline(self) -> datetime | None:
        return self.t0 + timedelta(minutes=DEADLINE_MINUTES) if self.t0 else None

    def to_json(self) -> dict:
        out: dict = {"kind": self.kind}
        if self.kind == "ring":
            out.update(alarmId=self.alarm_id, version=self.version, occurrenceId=f"{self.alarm_id}:{self.t0_local_date}",
                       t0=iso(self.t0), deadline=iso(self.deadline), mode=self.mode)
        return out


def classify(schedule: dict | None, d: date) -> str:
    """ring | paused | skipped | none for one alarm snapshot on d (only challenge alarms count)."""
    if not schedule or not schedule.get("enabled") or not schedule.get("countsForChallenge"):
        return "none"
    pause = schedule.get("pause")
    if pause and date.fromisoformat(pause["from"]) <= d <= date.fromisoformat(pause["to"]):
        return "paused"
    if schedule.get("kind") == "weekly":
        for ov in schedule.get("overrides", []):
            if ov["date"] == d.isoformat() and ov.get("skip"):
                return "skipped"
    return "ring" if local_time_for_date(schedule, d) else "none"


def day_plan(alarms: dict[str, list[dict]], d: date, tz_name: str) -> DayPlan:
    """alarms: alarm id → version history. Earliest ringing challenge alarm wins (ties: smaller alarm id); with no
    ring, a paused challenge alarm makes the day `paused`, else a skip makes it `skipped`, else `none`."""
    tz = ZoneInfo(tz_name)
    rings, kinds = [], set()
    for alarm_id, versions in alarms.items():
        v = snapshot(versions, d, tz)
        data = v["data"] if v else None
        kind = classify(data, d)
        kinds.add(kind)
        if kind == "ring":
            t0 = resolve_local(d, local_time_for_date(data, d), tz).astimezone(timezone.utc)
            rings.append((t0, alarm_id, v["version"], data["mode"]))
    if rings:
        t0, alarm_id, version, mode = min(rings, key=lambda r: (r[0], r[1]))
        return DayPlan("ring", alarm_id, version, t0, mode, t0_local_date=d.isoformat())
    for k in ("paused", "skipped"):
        if k in kinds:
            return DayPlan(k)
    return DayPlan("none")


# ---------------------------------------------------------------------------------------------------------------
# Session decision
# ---------------------------------------------------------------------------------------------------------------
def final_target(mode: dict, snoozes: int) -> int:
    t = mode["type"]
    if t == "sprint":
        return mode["minimumReps"]
    if t == "sets":
        return mode["sets"] * mode["repsPerSet"]
    if t == "escalation":
        return mode["targetReps"] + min(snoozes, mode["maxSnoozes"]) * mode["snoozeAddsReps"]
    return mode["targetReps"]


def decide(mode: dict, t0_ms: int, now_ms: int, session: dict) -> dict:
    """session (server-time epoch ms): {startedAt, endedAt, ringAt|None, outcome: completed|gaveUp|expired,
    snoozes, reps: [{tStart, tEnd, quality}], sets: [{start, end}] (sets mode), sprintStart|None (sprint mode)}.
    Returns {status, finalTargetReps, successAt|None, score, reason}."""
    deadline = t0_ms + DEADLINE_MINUTES * 60_000
    snoozes = min(session.get("snoozes", 0), mode.get("maxSnoozes", 0)) if mode["type"] == "escalation" else 0
    target = final_target(mode, snoozes)
    # Only reps after the ring (small clock tolerance) and before the deadline count for the challenge.
    reps = sorted((r for r in session["reps"] if r["tStart"] >= t0_ms - CLOCK_TOLERANCE_MS and r["tEnd"] <= deadline),
                  key=lambda r: r["tEnd"])
    t = mode["type"]
    success_at, score, reason = None, len(reps), "not_reached"

    if session["startedAt"] > deadline:
        reason = "started_after_deadline"
    elif t in ("ringUntilDone", "escalation"):
        if len(reps) >= target:
            success_at = reps[target - 1]["tEnd"]
    elif t == "beatTheClock":
        ring = session.get("ringAt")
        start = max(t0_ms, min(ring, deadline)) if ring is not None else t0_ms
        inside = [r for r in reps if r["tEnd"] <= start + mode["windowSeconds"] * 1000]
        score = len(inside)
        if len(inside) >= target:
            success_at = inside[target - 1]["tEnd"]
        elif len(reps) >= target:
            reason = "window_expired"
    elif t == "sprint":
        start = session.get("sprintStart")
        if start is None:
            reason = "sprint_not_started"
        elif start > deadline or start < t0_ms - CLOCK_TOLERANCE_MS:
            reason = "sprint_outside_deadline"
        else:
            end = start + mode["windowSeconds"] * 1000
            inside = [r for r in reps if start <= r["tStart"] and r["tEnd"] <= end]
            score = len(inside)
            if score >= mode["minimumReps"]:
                success_at = inside[mode["minimumReps"] - 1]["tEnd"]
            elif session["endedAt"] >= end or now_ms >= end:
                reason = "sprint_too_few"
    elif t == "sets":
        sets = sorted(session.get("sets", []), key=lambda s: s["start"])
        done, prev_end, broke = 0, None, False
        for s in sets:
            if prev_end is not None and s["start"] > prev_end + (mode["restSeconds"] + SET_START_GRACE_S) * 1000:
                broke = True
                break
            n = sum(1 for r in reps if s["start"] <= r["tStart"] and r["tEnd"] <= s["end"])
            if n < mode["repsPerSet"]:
                break
            done += 1
            prev_end = s["end"]
            if done == mode["sets"]:
                success_at = s["end"]
                break
        score = done
        if broke:
            reason = "rest_too_long"

    if success_at is not None:
        status, reason = "succeeded", "ok"
    elif session.get("outcome") == "gaveUp" or now_ms > deadline or reason in (
            "window_expired", "sprint_too_few", "rest_too_long", "sprint_outside_deadline"):
        status = "failed"
    else:
        status = "in_progress"
    if reason == "started_after_deadline":
        status = "missed"
    return {"status": status, "finalTargetReps": target, "successAt": success_at, "score": score, "reason": reason,
            "snoozesUsed": snoozes}


def wake_points(final_target_reps: int, mode_type: str, snoozes_used: int, avg_quality: int) -> int:
    """doc 08 §3 (integer math)."""
    base = 10
    difficulty = min(20, final_target_reps // 5)
    if mode_type in ("beatTheClock", "sprint", "sets"):
        bonus = 3
    elif mode_type == "escalation":
        bonus = -2 * snoozes_used
    else:
        bonus = 0
    quality = 3 if avg_quality >= 90 else (1 if avg_quality >= 75 else 0)
    return max(5, base + difficulty + bonus + quality)


# ---------------------------------------------------------------------------------------------------------------
# Streaks
# ---------------------------------------------------------------------------------------------------------------
def streak_fold(days: list[dict], freeze_grants: list[dict] | None = None) -> dict:
    """days: [{date, status}] (any order; unique dates). Statuses in_progress/scheduled/ringing are not decided yet
    and ignored. freeze_grants: [{date, count}] — added before that date is processed, capped at 2 stored.
    Days without a row (no challenge alarm) are neutral. Returns the final state + per-day effects."""
    grants = sorted(freeze_grants or [], key=lambda g: g["date"])
    gi = 0
    cur = best = pure = pure_best = freezes = 0
    paused_month, paused_count = None, 0
    last_counted = None
    effects = []
    for day in sorted(days, key=lambda x: x["date"]):
        d = day["date"]
        while gi < len(grants) and grants[gi]["date"] <= d:
            freezes = min(MAX_FREEZES, freezes + grants[gi]["count"])
            gi += 1
        status = day["status"]
        if status == "paused":
            month = d[:7]
            paused_count = paused_count + 1 if month == paused_month else 1
            paused_month = month
            if paused_count > MAX_PAUSED_DAYS_PER_MONTH:
                status = "missed"          # beyond the monthly pause allowance the day counts as missed
        effect = "neutral"
        if status == "succeeded":
            cur += 1
            pure += 1
            best, pure_best = max(best, cur), max(pure_best, pure)
            last_counted = d
            effect = "plus"
        elif status in ("failed", "missed"):
            pure = 0
            if freezes > 0:
                freezes -= 1
                effect = "freeze_used"
            else:
                cur = 0
                effect = "reset"
        effects.append({"date": d, "effect": effect})
    return {"current": cur, "best": best, "pureCurrent": pure, "pureBest": pure_best,
            "freezesAvailable": freezes, "lastCountedDate": last_counted, "effects": effects}


def iso(dt: datetime | None) -> str | None:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if dt else None
