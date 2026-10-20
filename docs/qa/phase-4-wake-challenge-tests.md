# Phase 4 — Wake Challenge end to end: device tests

CI proves the rules: the server (SQL), iOS and Android all pass the same wake vectors (decisions for all 5 modes,
points, streaks, schedule snapshots incl. DST) and rep-log checks; the result of a session is idempotent; late
uploads repair missed days. A real week on real phones is the exit test of the phase (roadmap Phase 4).
Sign in first — results are only verified for signed-in users (offline sessions upload later).

## Every mode once (set a test alarm 2–3 min ahead, challenge alarm on)
| # | Mode | Do | Expected |
|---|---|---|---|
| WK-01 | Ring until done, 10 | 10 push-ups | Alarm stops at 10, "Challenge beaten", then points + 🔥 streak after "Verifying…" |
| WK-02 | Beat the clock, 10 in 60 s | Start late (after 70 s) and finish | Alarm stops at 10, result "Challenge lost today" (window) |
| WK-03 | Sprint, 15 in 60 s | Get into plank → 3-2-1 → push-ups | Counter shows reps + seconds left; ≥ 15 beaten, < 15 lost |
| WK-04 | Sets 3 × 10, rest 45 s | Set, rest, set, rest, set | "Set 1 of 3", rest countdown, alarm rings loudly when the rest is over, beaten after set 3 |
| WK-05 | Sets — rest too long | Wait > rest + 30 s after a set | Challenge lost (rest too long), alarm stops |
| WK-06 | Escalation 10 (+5) | Snooze twice, then push-ups | Target 20 after two snoozes; points lower than without snooze |
| WK-07 | Give up | Hold "Give up" (Android) / confirm (iOS) | Alarm stops, lost, streak reset (unless a freeze) |

## Days and streak
| # | Test | Expected |
|---|---|---|
| WK-10 | Beat the challenge 3 mornings in a row | Wake tab 🔥 3, three green circles this week |
| WK-11 | Let one alarm ring out (no push-ups) | That day red (missed) on the Wake tab, streak 0 |
| WK-12 | "Skip next" the evening before | Day stays grey, streak unchanged |
| WK-13 | Change the alarm time 10 min before it rings | Today's challenge stays at the old time |
| WK-14 | Airplane mode at the wake-up, push-ups, then online 1 h later | "Will be verified when you're online" → later the day turns green |
| WK-15 | Free training 20 push-ups | Wake tab "push-ups today" includes them; streak unchanged |
| WK-16 | Practice ("Test my alarm") | Rings, counts, never changes the streak |

Note down anything that looks wrong (screenshot + time) — the server keeps every session, so each case can be
traced afterwards.
