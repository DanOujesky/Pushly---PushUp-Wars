# 10 — Stats, progress, achievements

Goal: stats that make users **proud** — colorful, animated, beautiful charts, and shareable.

## 1. Metrics tracked
Per user, per local day (personal) — from validated sessions (pending sessions shown with a dashed style):
| Metric | Notes |
|---|---|
| reps total / by context (wake, battle, training) | |
| sessions count | |
| best set (max consecutive valid reps in one set) | personal record |
| avg rep quality, avg depth, avg body-line | form trends |
| avg tempo (s/rep) | |
| wake: scheduled time, actual completion time, time-to-complete (ring → last rep), result | |
| streaks: current, best | |
| battles: W/L/draw by mode, trophies over time | |
| XP & level | |

Personal stats aggregate by **local** day (user's timezone at the time of the session), stored in `user_stats_local_daily` (separate from UTC competitive aggregates).

## 2. Dashboard (Profile → Stats)
> D-077: the Profile tab shows a **Your stats** card (level ring + XP, trophies + league, win rate, push-ups all time,
> best set, last 7 days bars, achievements progress); each part opens Stats on the matching section. Stats has three
> sections: **Battles** (trophy hero, players to beat, win-rate ring record, trophies chart, recent), **Push-ups**
> (everything below) and **Achievements** (progress header + all badges, unlocked first).

Top: period picker (Week / Month / Year / All) + 4 KPI tiles with sparkline (Total reps, Best set, Wake success %, Avg quality) each with Δ vs. previous period (green ↑ / red ↓).

Charts (Swift Charts on iOS, Vico on Android — same visual spec, design tokens from doc 14):
1. **Daily push-ups** — stacked bar by context (wake / battle / training), rounded bars, gradient fill, tap a bar → day detail.
2. **Cumulative push-ups** — area chart with gradient + milestone markers (1k, 5k, 10k…).
3. **Wake consistency** — dot plot: x = date, y = time of day; scheduled time as hollow ring, completion time as filled dot (green success / red fail); shaded band = target ±10 min.
4. **Best set over time** — line chart with PR markers (star) and trend line.
5. **Form score** — multi-line: quality, depth, body line (smoothed 7-day).
6. **Activity heatmap** — GitHub-style calendar for the year, intensity = reps (5-step sequential palette).
7. **Battle record** — donut by result + bar by mode win-rate; trophies line over the season with league bands in the background.
8. **Time of day** — radial/clock chart of when the user trains (Phase 6 polish).

Interactions: scrub with finger to see exact values (crosshair + tooltip); animated entry (bars grow, lines draw 600 ms ease-out); respects Reduce Motion.

## 3. Personal records & milestones
- PRs: best set, best wake time-to-complete per target, most reps in a day/week, longest streak, fastest 20 (speed), best 60 s max reps.
- New PR → confetti + "New record!" card + share.
- Milestones: total reps 100 / 500 / 1k / 2.5k / 5k / 10k / 25k / 50k / 100k.

## 4. Achievements (badges)
Data-driven: `achievement_definitions (id, title, description, icon, tier, rule jsonb, xp)` evaluated server-side after each validated session (`evaluate_achievements(user_id)`).
Initial set (≥ 40 in v1), examples:
| Group | Examples |
|---|---|
| Wake | First Wake, Early Bird (10 wakes before 6:00 local), Iron Morning (30-day streak), Unbreakable (100-day streak) |
| Volume | Century (100 in a day), 1K Club, 10K Legend |
| Form | Perfect Ten (10 reps quality ≥ 95), Textbook (session avg ≥ 90) |
| Battles | First Blood, Hat-trick (3 wins in a row), Mode Master (win every mode), Giant Slayer (beat someone 500+ trophies higher) |
| Clans | Team Player (first war), MVP, War Machine (10 war wins) |
| Social | Squad (5 friends), Recruiter (invite 3 friends who join) |
Rewards: XP, sometimes a streak freeze (max 2 stored), cosmetic items.

## 5. XP & levels
XP: 1 per verified rep, +20 per succeeded wake, +15 per battle win, +5 per battle loss, achievement XP. Level `n` requires `100 × n^1.5` cumulative XP (rounded). Level shown on profile; cosmetic unlocks at levels 5, 10, 20, 30, 50.

## 6. Share cards
Generated on device (SwiftUI `ImageRenderer` / Compose to bitmap), 1080×1920 and 1080×1080: big number, chart snippet, streak, Pushly logo + `pushly.app` link. No personal data beyond username unless the user enables it.
