"""Reference rules for account data (doc 02 PS-03, doc 16 §2) and app version comparison (doc 03 §7).
Must match the server (`update_profile`, `username_available` in migration 0002) and both apps."""
from __future__ import annotations

import re

USERNAME_RE = re.compile(r"^[A-Za-z0-9_.]{3,20}$")
PLACEHOLDER_RE = re.compile(r"^u_[0-9a-f]{12}$")
MIN_AGE = 16
MIN_BIRTH_YEAR = 1900


def username_error(name: str) -> str | None:
    """None if valid, else an error code the UI maps to a message."""
    if len(name) < 3:
        return "tooShort"
    if len(name) > 20:
        return "tooLong"
    if not USERNAME_RE.match(name):
        return "invalidCharacters"
    if PLACEHOLDER_RE.match(name):
        return "reserved"
    return None


def birth_year_error(birth_year: int, current_year: int) -> str | None:
    if birth_year < MIN_BIRTH_YEAR or birth_year > current_year:
        return "invalid"
    if current_year - birth_year < MIN_AGE:
        return "tooYoung"
    return None


def parse_version(v: str) -> tuple[int, int, int]:
    """'1.2' -> (1, 2, 0); '1.2.3 (45)' -> (1, 2, 3). Non-numeric parts raise ValueError."""
    core = v.strip().split(" ")[0]
    parts = core.split(".")
    if not 1 <= len(parts) <= 3 or not all(p.isdigit() for p in parts):
        raise ValueError(v)
    nums = [int(p) for p in parts] + [0] * (3 - len(parts))
    return nums[0], nums[1], nums[2]


def update_required(app_version: str, min_supported: str) -> bool:
    return parse_version(app_version) < parse_version(min_supported)
