"""Which OS alarms the apps must have armed (doc 04 §5.2, §5.3, §6.2). Pure; generates shared/test-vectors/alarm-plan.

iOS (AlarmKit): every occurrence in the rolling window gets a main alarm; the challenge occurrence of each local date
also gets a nag chain at T0 + 2, 4, 6 … min (strictly before the deadline T0 + 30 min). Each OS alarm has a
deterministic UUIDv5 id so `sync` can diff desired vs. scheduled alarms idempotently.

Android (AlarmManager): only the next occurrence of every enabled alarm is armed (setAlarmClock); re-armed after each ring.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from .occurrences import Occurrence, all_occurrences, challenge_occurrence, occurrences

# Namespace for OS alarm ids. Never change: alarms already scheduled on devices are matched by these ids.
NAMESPACE = uuid.UUID("6f1c2a52-8b9e-4c1e-9a43-2a1d5e0c7b11")
NAG_INTERVAL_MINUTES = 2
DEADLINE_MINUTES = 30
ANDROID_LOOKAHEAD_DAYS = 400  # long enough for one-off alarms, overrides and the longest pause


def os_alarm_id(occurrence_id: str, role: str) -> str:
    """role = "main" or "nag1", "nag2", …"""
    return str(uuid.uuid5(NAMESPACE, f"{occurrence_id}#{role}"))


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ios_plan(schedules: list[dict], from_instant: datetime, tz_name: str, window_days: int, nag_count: int) -> list[dict]:
    occ = all_occurrences(schedules, from_instant, tz_name, window_days)
    challenge_ids = set()
    for d in sorted({o.local_date for o in occ}):
        c = challenge_occurrence(d, occ)
        if c:
            challenge_ids.add(c.occurrence_id)
    out: list[dict] = []
    for o in occ:
        out.append(_entry(o, "main", o.instant))
        if o.occurrence_id in challenge_ids:
            deadline = o.instant + timedelta(minutes=DEADLINE_MINUTES)
            for n in range(1, nag_count + 1):
                at = o.instant + timedelta(minutes=NAG_INTERVAL_MINUTES * n)
                if at < deadline:
                    out.append(_entry(o, f"nag{n}", at))
    out.sort(key=lambda e: (e["fireAt"], e["osAlarmId"]))
    return out


def _entry(o: Occurrence, role: str, at: datetime) -> dict:
    return {"osAlarmId": os_alarm_id(o.occurrence_id, role), "occurrenceId": o.occurrence_id, "alarmId": o.alarm_id,
            "role": role, "fireAt": _iso(at), "countsForChallenge": o.counts_for_challenge}


def android_next(schedules: list[dict], from_instant: datetime, tz_name: str) -> dict[str, dict | None]:
    out: dict[str, dict | None] = {}
    for s in schedules:
        occ = occurrences(s, from_instant, tz_name, ANDROID_LOOKAHEAD_DAYS)
        out[s["id"]] = {"occurrenceId": occ[0].occurrence_id, "fireAt": _iso(occ[0].instant)} if occ else None
    return out
