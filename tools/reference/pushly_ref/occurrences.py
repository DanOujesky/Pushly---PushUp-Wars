"""Reference implementation of alarm occurrence computation (doc 04 §2, §4).

This is the executable specification used to generate shared/test-vectors/alarm-occurrences.
Swift and Kotlin implementations must produce identical results for every vector.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
MAX_GAP_MINUTES = 180  # longest DST gap we support (real gaps are 30 or 60 min)


@dataclass(frozen=True)
class Occurrence:
    occurrence_id: str
    alarm_id: str
    local_date: date
    instant: datetime  # aware, UTC
    counts_for_challenge: bool

    def to_json(self) -> dict:
        return {
            "occurrenceId": self.occurrence_id,
            "alarmId": self.alarm_id,
            "localDate": self.local_date.isoformat(),
            "instant": self.instant.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "countsForChallenge": self.counts_for_challenge,
        }


class ScheduleError(ValueError):
    pass


def parse_hhmm(value: str) -> time:
    m = TIME_RE.match(value or "")
    if not m:
        raise ScheduleError(f"invalid time {value!r} (expected HH:mm)")
    return time(int(m.group(1)), int(m.group(2)))


def resolve_local(d: date, t: time, tz: ZoneInfo) -> datetime:
    """Local wall-clock date+time -> aware datetime, applying DST rules from doc 04 §4:
    gap  -> first valid minute after the gap; overlap -> first (earlier) instance."""
    naive = datetime.combine(d, t)
    for minutes in range(0, MAX_GAP_MINUTES + 1):
        candidate = naive + timedelta(minutes=minutes)
        aware = candidate.replace(tzinfo=tz, fold=0)  # fold=0 => earlier instance in an overlap
        round_trip = aware.astimezone(timezone.utc).astimezone(tz).replace(tzinfo=None)
        if round_trip == candidate:
            return aware
    raise ScheduleError(f"could not resolve {naive} in {tz.key}")


def local_time_for_date(schedule: dict, d: date) -> time | None:
    """Which wall-clock time (if any) the alarm rings on local date d. Pure schedule logic, no time zones."""
    if not schedule.get("enabled", False):
        return None
    pause = schedule.get("pause")
    if pause and date.fromisoformat(pause["from"]) <= d <= date.fromisoformat(pause["to"]):
        return None

    kind = schedule["kind"]
    if kind == "oneOff":
        one = datetime.fromisoformat(schedule["oneOff"])
        return one.time() if one.date() == d else None
    if kind != "weekly":
        raise ScheduleError(f"unknown kind {kind!r}")

    for ov in schedule.get("overrides", []):
        if ov["date"] == d.isoformat():
            if ov.get("skip"):
                return None
            return parse_hhmm(ov["time"])

    value = schedule["weekly"].get(WEEKDAYS[d.weekday()])
    return parse_hhmm(value) if value else None


def occurrences(schedule: dict, from_instant: datetime, tz_name: str, horizon_days: int) -> list[Occurrence]:
    """All occurrences of one alarm for local dates [today, today + horizon_days] (inclusive) whose instant
    is strictly after from_instant, sorted by instant."""
    tz = ZoneInfo(tz_name)
    today = from_instant.astimezone(tz).date()
    out: list[Occurrence] = []
    for offset in range(horizon_days + 1):
        d = today + timedelta(days=offset)
        t = local_time_for_date(schedule, d)
        if t is None:
            continue
        instant = resolve_local(d, t, tz).astimezone(timezone.utc)
        if instant <= from_instant:
            continue
        out.append(Occurrence(
            occurrence_id=f"{schedule['id']}:{d.isoformat()}",
            alarm_id=schedule["id"],
            local_date=d,
            instant=instant,
            counts_for_challenge=bool(schedule.get("countsForChallenge", False)),
        ))
    out.sort(key=lambda o: (o.instant, o.alarm_id))
    return out


def all_occurrences(schedules: list[dict], from_instant: datetime, tz_name: str, horizon_days: int) -> list[Occurrence]:
    out = [o for s in schedules for o in occurrences(s, from_instant, tz_name, horizon_days)]
    out.sort(key=lambda o: (o.instant, o.alarm_id))
    return out


def challenge_occurrence(local_date: date, occs: list[Occurrence]) -> Occurrence | None:
    """The single occurrence that counts for the Wake Challenge on a local date (doc 04 §1):
    the earliest enabled challenge-alarm occurrence; ties broken by alarm id (lexicographic)."""
    candidates = [o for o in occs if o.local_date == local_date and o.counts_for_challenge]
    return min(candidates, key=lambda o: (o.instant, o.alarm_id), default=None)
