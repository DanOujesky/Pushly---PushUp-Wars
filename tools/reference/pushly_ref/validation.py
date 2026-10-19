"""AlarmSchedule validation rules (doc 04 §2). Returns a list of error codes; empty list = valid."""
from __future__ import annotations

from datetime import date, datetime

from .occurrences import TIME_RE, WEEKDAYS


def _in(v, lo, hi) -> bool:
    return isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi


def validate_schedule(s: dict, today: date) -> list[str]:
    errors: list[str] = []
    kind = s.get("kind")
    if kind not in ("weekly", "oneOff"):
        errors.append("kind.invalid")
    if kind == "weekly":
        weekly = s.get("weekly") or {}
        if set(weekly) - set(WEEKDAYS):
            errors.append("weekly.unknownDay")
        for day, value in weekly.items():
            if value is not None and not TIME_RE.match(str(value)):
                errors.append(f"weekly.{day}.time")
        if not any(weekly.get(d) for d in WEEKDAYS) and not s.get("overrides"):
            errors.append("weekly.empty")
        overrides = s.get("overrides", [])
        if len(overrides) > 60:
            errors.append("overrides.tooMany")
        seen = set()
        for ov in overrides:
            try:
                d = date.fromisoformat(ov["date"])
            except (KeyError, ValueError):
                errors.append("overrides.date")
                continue
            if d < today:
                errors.append("overrides.past")
            if d in seen:
                errors.append("overrides.duplicate")
            seen.add(d)
            if not ov.get("skip") and not TIME_RE.match(str(ov.get("time", ""))):
                errors.append("overrides.time")
    if kind == "oneOff":
        try:
            datetime.fromisoformat(s["oneOff"])
        except (KeyError, ValueError, TypeError):
            errors.append("oneOff.invalid")

    pause = s.get("pause")
    if pause:
        try:
            f, t = date.fromisoformat(pause["from"]), date.fromisoformat(pause["to"])
            if t < f:
                errors.append("pause.order")
            elif (t - f).days + 1 > 30:
                errors.append("pause.tooLong")
        except (KeyError, ValueError):
            errors.append("pause.invalid")

    mode = s.get("mode") or {}
    mt = mode.get("type")
    if mt in ("ringUntilDone", "beatTheClock", "escalation"):
        if not _in(mode.get("targetReps"), 5, 100):
            errors.append("mode.targetReps")
    if mt == "beatTheClock" and not _in(mode.get("windowSeconds"), 30, 600):
        errors.append("mode.windowSeconds")
    if mt == "sprint":
        if mode.get("windowSeconds") not in (30, 60, 120):
            errors.append("mode.windowSeconds")
        if not _in(mode.get("minimumReps"), 5, 100):
            errors.append("mode.minimumReps")
    if mt == "sets":
        if not _in(mode.get("sets"), 2, 5):
            errors.append("mode.sets")
        if not _in(mode.get("repsPerSet"), 5, 50):
            errors.append("mode.repsPerSet")
        if not _in(mode.get("restSeconds"), 15, 180):
            errors.append("mode.restSeconds")
    if mt == "escalation":
        if not _in(mode.get("snoozeAddsReps"), 1, 20):
            errors.append("mode.snoozeAddsReps")
        if not _in(mode.get("snoozeMinutes"), 1, 10):
            errors.append("mode.snoozeMinutes")
        if not _in(mode.get("maxSnoozes"), 1, 5):
            errors.append("mode.maxSnoozes")
    if mt not in ("ringUntilDone", "beatTheClock", "sprint", "sets", "escalation"):
        errors.append("mode.type")
    return errors
