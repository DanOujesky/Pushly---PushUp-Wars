# 08 — Ranking, trophies, leagues & leaderboards

## 1. Two ratings
| Rating | Visible | Purpose | Math |
|---|---|---|---|
| **Trophies** | ✅ | progression, leagues, battle leaderboards | integer rules below (§2) |
| **MMR** | ❌ hidden | fair matchmaking | **Glicko-2** (rating 1500, RD 350, volatility 0.06, τ = 0.5), updated after every ranked battle |

## 2. Trophies (integer math only; test vectors in `shared/test-vectors/trophies`)
### 2.1 Per ranked battle
Let `me`, `opp` = trophies before the battle.
```
diff     = opp - me
winGain  = clamp(30 + diff / 25, 10, 50)       // integer division truncating toward zero
lossCost = clamp(20 - diff / 25, 5, 40)
```
- Win: `me += winGain`; Loss: `me -= lossCost` (never below the floor, §2.3). Draw (only possible via void-free exact tie after all tie-breaks): ±0.
- **Placement:** the first 5 ranked battles of an account: wins ×1.5 (rounded down), losses ×0.5 (rounded down).
- **Win streak bonus:** 3rd+ consecutive ranked win: +3 (max +3).

### 2.2 Leagues
| League | Trophies | Tiers |
|---|---|---|
| Bronze | 0 – 599 | III, II, I |
| Silver | 600 – 1199 | III, II, I |
| Gold | 1200 – 1999 | III, II, I |
| Platinum | 2000 – 2999 | III, II, I |
| Diamond | 3000 – 3999 | III, II, I |
| Champion | 4000 – 4999 | — |
| Legend | 5000+ | — (top 100 global shown with number, e.g. "Legend #17") |

Tier rule: a league range `[lo, hi]` is split into three parts with `size = (hi - lo + 1) / 3` (integer division): III = `[lo, lo+size-1]`, II = `[lo+size, lo+2·size-1]`, I = `[lo+2·size, hi]`. Example Gold: III 1200–1465, II 1466–1731, I 1732–1999. Implement as one shared function `leagueFor(trophies)` with test vectors.

### 2.3 Floors
Once a player reaches **600**, **1200** or **2000** within a season, they can't drop below that value until the season ends.

### 2.4 Reversal
If a battle is voided by anti-cheat after settlement: the cheater's gain is reverted; the victim's loss is refunded; the victim is **not** given the win. All via `trophy_ledger` compensating entries (never edit history).

### 2.5 Seasons
- Calendar month UTC. At season end (`pg_cron` 1st day 00:05 UTC):
  - rewards by best league reached (cosmetic: badge, profile frame, emote), granted into `inventory`;
  - soft reset: `t > 2000 → 2000 + (t - 2000) / 2`; `t ≤ 2000` unchanged; floors cleared.
- Season leaderboards are archived to `season_results`.

## 3. Wake Score
Points per `succeeded` wake attempt (server-computed):
```
base       = 10
difficulty = min(20, finalTargetReps / 5)            // integer division
modeBonus  = beatTheClock|sprint|sets: +3 ; ringUntilDone: 0 ; escalation: -2 × snoozesUsed (min total 5)
quality    = avgQuality ≥ 90 ? +3 : (avgQuality ≥ 75 ? +1 : 0)
points     = max(5, base + difficulty + modeBonus + quality)
```
- `failed`/`missed`: 0 points (streak handled in doc 04 §7).
- Maximum 1 counted attempt per local day (doc 04 §1).

**Pure streak vs. personal streak:** the personal streak (Wake tab, profile) may be saved by streak freezes. Because freezes can come from Pro or rewarded ads, the **leaderboard** uses the *pure streak*, which resets on every `failed`/`missed` day even if a freeze was consumed. `skipped`, `paused` (within limits) and `void` freeze both streaks equally. Store both in `streaks` (`pure_current`, `pure_best`).

## 4. Leaderboards
| Board | Metric | Scopes | Periods |
|---|---|---|---|
| **Wake** | Wake Score sum | global, country, friends, clan | week, month (season), all-time |
| **Wake streak** | current **pure streak** (ties: longer best pure streak) | global, country, friends, clan | current |
| **Battles** | trophies | global, country, friends, clan | season (current), previous seasons |
| **Total push-ups** | verified reps (all contexts) | global, country, friends, clan | today, week, month, all-time |
| **Clans** | clan trophies; Clan War weekly score | global, country | season, this week |

- Periods for global competitive boards are **UTC** (CLAUDE.md §6). The UI labels them ("Week resets Monday 02:00 your time").
- Only `verified` sessions of users with `trust_score ≥ 50` and `leaderboard_visible = true` (else shown as "Anonymous athlete") appear. Low-trust users see themselves at their "would-be" rank only on their own device (shadow mode, doc 06).
- Pagination: top 100 + "around me" (±10). Own row pinned.

### 4.1 Implementation
- Source tables: `user_stats_daily` (per user per UTC day: reps_total, reps_wake, reps_battle, reps_training, wake_points), updated by `submit-rep-session` / `settle-battle` inside the same transaction.
- Aggregates: `user_stats_weekly`, `user_stats_monthly`, `user_stats_alltime` maintained incrementally (upserts) — never full recompute in a request path.
- **Global/country boards:** `pg_cron` every 60 s refreshes `leaderboard_snapshots (board, scope, scope_key, period_key, rank, user_id, score)` for the top 1,000 per board/scope using window functions; reads come from snapshots.
- **My rank** outside top 1,000: RPC `my_rank(board, scope, period)` = `1 + count(*) where score > my_score` on the aggregate table (index on `(period_key, score desc)`).
- **Friends / clan boards:** computed on request (≤ 500 friends / 30 members) by RPC with RLS-safe `SECURITY DEFINER` function that only returns users related to the caller.
- Cache on client 60 s; Realtime not used for leaderboards (except clan war ticker).
