"""Hand-labelled AdsGate cases (doc 13 §1). build_vectors.py asserts them and writes shared/test-vectors/ads/gate.json."""

NOW = 1_800_000_000_000
MIN = 60_000

BASE = {"isPro": False, "wakeActive": False, "lastWakeEndedMs": None, "cameraActive": False, "battlePhase": "none",
        "screen": "other", "completedSessions": 5, "nowMs": NOW, "lastTapMs": None, "shown": [],
        "battlesSinceInterstitial": 3, "freezesAvailable": 0}


def ctx(**over) -> dict:
    return {**BASE, **over}


def shown(placement: str, *minutes_ago: int) -> list[dict]:
    return [{"placement": placement, "atMs": NOW - m * MIN} for m in minutes_ago]


CASES = [
    ("banner-ok", "ranks_banner", ctx(), True, "ok"),
    ("unknown", "splash_video", ctx(), False, "unknown_placement"),
    ("pro-never", "ranks_banner", ctx(isPro=True), False, "pro"),
    ("wake-active", "stats_banner", ctx(wakeActive=True), False, "wake_active"),
    ("wake-9-min-ago", "stats_banner", ctx(lastWakeEndedMs=NOW - 9 * MIN), False, "wake_cooldown"),
    ("wake-10-min-ago", "stats_banner", ctx(lastWakeEndedMs=NOW - 10 * MIN), True, "ok"),
    ("camera", "ranks_banner", ctx(cameraActive=True), False, "camera_active"),
    ("matchmaking", "ranks_banner", ctx(battlePhase="matchmaking"), False, "battle_active"),
    ("battle-results-still-open", "battle_results_interstitial", ctx(battlePhase="results"), False, "battle_active"),
    ("alarm-editor", "ranks_banner", ctx(screen="alarm_editor"), False, "forbidden_screen"),
    ("alarm-health", "ranks_banner", ctx(screen="alarm_health"), False, "forbidden_screen"),
    ("onboarding", "ranks_banner", ctx(screen="onboarding"), False, "forbidden_screen"),
    ("first-session", "ranks_banner", ctx(completedSessions=1), False, "new_user"),
    ("interstitial-ok", "battle_results_interstitial", ctx(), True, "ok"),
    ("interstitial-1-battle", "battle_results_interstitial", ctx(battlesSinceInterstitial=1), False, "battle_frequency"),
    ("interstitial-2-battles", "battle_results_interstitial", ctx(battlesSinceInterstitial=2), True, "ok"),
    ("interstitial-new-user", "battle_results_interstitial", ctx(completedSessions=4), False, "new_user"),
    ("banner-after-2-sessions", "stats_banner", ctx(completedSessions=2), True, "ok"),
    ("interstitial-right-after-tap", "battle_results_interstitial", ctx(lastTapMs=NOW - 1500), False, "tap_guard"),
    ("interstitial-14-min-gap", "battle_results_interstitial", ctx(shown=shown("battle_results_interstitial", 14)), False, "min_gap"),
    ("interstitial-15-min-gap", "battle_results_interstitial", ctx(shown=shown("battle_results_interstitial", 15)), True, "ok"),
    ("interstitial-4-today", "battle_results_interstitial",
     ctx(shown=shown("battle_results_interstitial", 20, 60, 120, 300)), False, "daily_cap"),
    ("interstitial-4-but-old", "battle_results_interstitial",
     ctx(shown=shown("battle_results_interstitial", 20, 60, 120, 25 * 60)), True, "ok"),
    ("global-cap", "rewarded_extra_ghost",
     ctx(shown=shown("battle_results_interstitial", 10, 20, 30, 40, 50, 60) + shown("rewarded_extra_ghost", 5, 6)),
     False, "global_cap"),
    ("banners-ignore-global-cap", "clan_banner",
     ctx(shown=shown("battle_results_interstitial", 10, 20, 30, 40, 50, 60) + shown("rewarded_extra_ghost", 5, 6)), True, "ok"),
    ("freeze-ad-has-freeze", "rewarded_streak_freeze", ctx(freezesAvailable=1), False, "has_freeze"),
    ("freeze-ad-this-week", "rewarded_streak_freeze", ctx(shown=shown("rewarded_streak_freeze", 6 * 24 * 60)), False, "weekly_cap"),
    ("freeze-ad-ok", "rewarded_streak_freeze", ctx(shown=shown("rewarded_streak_freeze", 7 * 24 * 60)), True, "ok"),
    ("rewarded-ignores-tap-guard", "rewarded_extra_ghost", ctx(lastTapMs=NOW - 100), True, "ok"),
    ("ghost-3-today", "rewarded_extra_ghost", ctx(shown=shown("rewarded_extra_ghost", 1, 2, 3)), False, "daily_cap"),
]
