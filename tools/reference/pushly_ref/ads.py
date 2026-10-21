"""AdsGate (doc 13 §1, CLAUDE.md §4.5) — when an ad may be shown. Executable reference for iOS + Android `AdsGate`.

can_show(placement, ctx) -> (allowed, reason). Every ad call in the apps goes through AdsGate; the first failing rule
is the reason. Times are epoch ms; "day" caps are rolling 24 h windows (no time zone involved).

ctx keys: isPro, wakeActive, lastWakeEndedMs (or None), cameraActive, battlePhase (none | matchmaking | lobby | live |
results), screen (other | onboarding | alarm_editor | alarm_health | wake | camera | battle), completedSessions, nowMs,
lastTapMs (or None), shown: [{placement, atMs}], battlesSinceInterstitial, freezesAvailable.
"""
from __future__ import annotations

DAY = 24 * 3600 * 1000
WAKE_COOLDOWN_MS = 10 * 60 * 1000
TAP_GUARD_MS = 2000
INTERSTITIAL_GAP_MS = 4 * 60 * 1000

PLACEMENTS = {
    "battle_results_interstitial": "interstitial",
    "ranks_banner": "banner",
    "stats_banner": "banner",
    "clan_banner": "banner",
    "rewarded_streak_freeze": "rewarded",
    "rewarded_extra_ghost": "rewarded",
}
FORBIDDEN_SCREENS = {"onboarding", "alarm_editor", "alarm_health", "wake", "camera", "battle"}
BUSY_BATTLE = {"matchmaking", "lobby", "live", "results"}


def _count(shown: list[dict], now: int, window: int, placements: set[str]) -> int:
    return sum(1 for s in shown if s["placement"] in placements and now - s["atMs"] < window)


def can_show(placement: str, ctx: dict) -> tuple[bool, str]:
    kind = PLACEMENTS.get(placement)
    if kind is None:
        return False, "unknown_placement"
    now = ctx["nowMs"]
    if ctx.get("isPro"):
        return False, "pro"
    if ctx.get("wakeActive"):
        return False, "wake_active"
    last_wake = ctx.get("lastWakeEndedMs")
    if last_wake is not None and now - last_wake < WAKE_COOLDOWN_MS:
        return False, "wake_cooldown"
    if ctx.get("cameraActive"):
        return False, "camera_active"
    if ctx.get("battlePhase", "none") in BUSY_BATTLE:
        return False, "battle_active"
    if ctx.get("screen", "other") in FORBIDDEN_SCREENS:
        return False, "forbidden_screen"
    if ctx.get("completedSessions", 0) < 2:
        return False, "new_user"
    shown = ctx.get("shown", [])
    if kind in ("interstitial", "rewarded"):
        if _count(shown, now, DAY, {p for p, k in PLACEMENTS.items() if k != "banner"}) >= 8:
            return False, "global_cap"
    if kind == "interstitial":
        last_tap = ctx.get("lastTapMs")
        if last_tap is not None and now - last_tap < TAP_GUARD_MS:
            return False, "tap_guard"
    if placement == "battle_results_interstitial":
        if ctx.get("battlesSinceInterstitial", 0) < 3:
            return False, "battle_frequency"
        recent = [s["atMs"] for s in shown if s["placement"] == placement]
        if recent and now - max(recent) < INTERSTITIAL_GAP_MS:
            return False, "min_gap"
        if _count(shown, now, DAY, {placement}) >= 6:
            return False, "daily_cap"
    if placement == "rewarded_streak_freeze":
        if ctx.get("freezesAvailable", 0) > 0:
            return False, "has_freeze"
        if _count(shown, now, 7 * DAY, {placement}) >= 1:
            return False, "weekly_cap"
    if placement == "rewarded_extra_ghost" and _count(shown, now, DAY, {placement}) >= 3:
        return False, "daily_cap"
    return True, "ok"
