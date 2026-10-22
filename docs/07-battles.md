# 07 — Battles (real-time 1v1)

## 1. Battle types
| Type | Who | Changes trophies? |
|---|---|---|
| **Quick match (ranked)** | random opponent via matchmaking | ✅ |
| **Friend – ranked** | a friend; both must accept "Ranked" | ✅ (max 3 counted per pair per day, doc 06 §7) |
| **Friend – friendly** | a friend | ❌ (stats & totals only) |
| **Ghost** | asynchronous: you vs. a recorded rep timeline of a real player (or your PB) | ❌ |

All battle reps count towards personal totals and Clan Wars (subject to doc 09 caps).

## 2. Modes — exact rules
All modes: camera-verified reps only (doc 05, competitive bounds), plank-start required, server-synchronised start.

| Mode | ID | Rules | Win condition | Tie-break |
|---|---|---|---|---|
| **Max Reps** | `max_reps` | duration 30 / **60** / 120 s; both go at the same time | more valid reps | higher average quality → earlier time of last rep |
| **Best of 3** | `best_of_3` | 3 rounds, each round = **one continuous set**; a set ends when the player pauses > 2 s (any position), leaves plank, or hits 90 s; 45 s rest between rounds | first to win 2 rounds | a tied round has no winner; if still tied after 3 rounds → total reps → avg quality |
| **Speed** | `speed` | first to N reps (10 / **20** / 30); cap 120 s | reach N first (server-synced time of the N-th rep end) | if nobody reaches N: more reps → earlier last rep |
| **Turns** | `turns` | players alternate single reps; after opponent's rep completes, you have **5 s** to complete one valid rep; between turns you must **hold the top plank** (leaving plank > 2 s = loss); first turn decided by coin flip | opponent misses the turn window, does an invalid rep, or leaves plank | cap 200 total reps → more average quality |
| **Endurance** | `endurance` | both continuous; your set ends when you pause > 3 s or leave plank; cap 10 min | higher total | earlier finish of the last rep |

Mode availability: Quick match queues exist for `max_reps` (60 s), `best_of_3`, `speed` (20). `turns` and `endurance` are **friend-only** in v1 (latency-sensitive / long). Configurable variants (30/120 s, 10/30 reps) are friend-only.

## 3. Matchmaking (quick match)
- Edge Function `matchmaking-join` puts the user into `matchmaking_queue (user_id, mode, mmr, region, joined_at)`.
- A `pg_cron` job every **2 s** (or a Postgres function triggered on insert) pairs players:
  - same mode; region preference by continent (from IP at join), cross-region allowed after 20 s;
  - MMR window: ±100 at 0 s, widening +50 every 5 s, max ±400 at 30 s;
  - never the same opponent twice in a row within 10 min;
  - trust-score buckets (doc 06 §1): low-trust users are matched only with each other.
- On match: create `battles` row (status `lobby`), notify both via Realtime channel `user:{id}` (`match_found`).
- No opponent after 45 s → offer **Ghost battle** or keep waiting (queue max 3 min).

## 4. Battle lifecycle & protocol

```
created → lobby → ready_check → countdown → live → (round_rest → live)* → finished → settled
                           └─► cancelled (someone left before countdown)
                                     live ─► void (both disconnected / integrity failure)
```

1. **lobby:** both clients call Edge Function `battle-token` → receive a LiveKit token (room `battle-{id}`, grants only for these two users, TTL 15 min) and join the room. They subscribe to Supabase Realtime channel `battle:{id}` (broadcast + presence).
2. **ready_check:** each client must report `body_ready` (full body visible, plank detected) within 30 s; otherwise the missing player forfeits (ranked: counts as loss only if the opponent was ready; first offence per day = no trophy loss).
3. **Clock sync:** before countdown each client runs 5 ping/pong exchanges with the `battle-clock` Edge Function (or a Realtime echo), takes the sample with minimum RTT and computes `serverOffsetMs`. All rep events are expressed in **server time**.
4. **countdown:** server broadcasts `start { startAtServerMs: now + 3500 }`. Clients show 3-2-1-GO aligned to `startAtServerMs`.
5. **live:**
   - Each client sends rep events over the **LiveKit data channel** (reliable mode) to the opponent for instant UI: `{type:"rep", i, tEndServerMs, quality}` and optionally its skeleton at 10 Hz (`{type:"pose", lm:[...13 key points]}`) for an overlay.
   - Each client **also** sends rep events to the server via RPC `battle_push_rep(battle_id, round, i, t_end_server_ms, quality)` (fire-and-forget, batched every 250 ms). The server stores them in `battle_events` with its receive time and re-broadcasts the authoritative score on `battle:{id}` (`score {a, b}`) — used for live clan-war tickers and spectating later.
   - **Turns mode:** turn windows are computed from the opponent's rep `tEndServerMs`; the client shows the 5 s ring countdown. Latency compensation: window = 5 s + min(opponent one-way latency, 500 ms).
6. **finished:** when the mode's end condition is met (client-side display) each client uploads its **signed rep log** for the battle (`submit-rep-session` with `context.type = battle`) within 30 s.
7. **settled:** Edge Function `settle-battle` (triggered when both logs arrive or after 30 s timeout) validates both logs (doc 06), recomputes the result **from the logs**, writes `battles.result`, applies trophies/MMR (doc 08), writes `trophy_ledger`, broadcasts `settled { winner, trophiesDelta }`. UI shows provisional result immediately, then animates to the settled one.

### Disconnects
- Reconnect grace **10 s** (LiveKit + Realtime presence). During grace the disconnected player's counter freezes.
- One player gone > 10 s → that player loses (ranked). Both gone → `void`.
- Missing rep log after 30 s → player's result computed from server-received `battle_events` but capped at the count of those events, and flagged.

## 5. Video & camera sharing
- LiveKit Cloud (SFU) — Swift SDK on iOS, Android SDK (+ Compose components) on Android. Self-hosting LiveKit (open source) is a later cost option.
- **One camera, two consumers:** the app's own camera pipeline captures frames once; frames go to MediaPipe **and** are published to LiveKit via a custom video source (iOS: LiveKit `BufferCapturer` fed from our `AVCaptureVideoDataOutput`; Android: custom `VideoCapturer` fed from the CameraX `ImageAnalysis` stream). Never open the camera twice.
- Publish 540p @ 24 fps with simulcast (low layer 270p) — adaptive; prioritise our pose analysis over video encoding when CPU-bound (drop video fps first).
- **Audio:** ranked = microphones off (no voice chat with strangers). Friendly = mic toggle, default off.
- **Nothing is recorded** (no LiveKit Egress). State this in the privacy policy.
- Opponent video shows an optional skeleton overlay from their pose events (transparency: you can see what their app counts).

## 6. UI
- Portrait: opponent top half, you bottom half (your preview mirrored). Landscape: side by side.
- Huge counters in each half; rep "pop" animation + haptic; opponent's reps pop on their half.
- Mode-specific HUD: timer ring (max_reps), round dots (best_of_3), progress bar to N (speed), turn indicator + 5 s ring (turns), set-alive pulse (endurance).
- Results: winner banner, both counts, quality, trophies ± with animated counter, league progress bar, "Rematch" (friend battles), "Report", "Share".
- Battle history list: opponent, mode, result, trophies Δ, date.

## 7. Ghost battles
- Ghost data = a validated battle/training rep log's timeline (rep `tEnd` offsets + per-rep quality) of a player with similar MMR, anonymised unless the user is a friend / PB. Stored in `ghost_runs` (only users with public profiles contribute; opt-out in privacy settings).
- Plays back as an animated avatar + counter (no video).

### 7.1 Practice bots (D-063)
- **Computer opponents, always labelled**: the opponent is shown as "🤖 Bot · <Level>" everywhere (live HUD, result,
  history). A bot is a synthetic rep timeline generated on the server (`start_bot_battle(mode, level)`), never a fake
  person: no profile, no leaderboard entry, no clan, never ranked, no trophies (ghost rules: XP only).
- Levels: Beginner (~15 reps/min), Rookie (~22), Athlete (~28), Pro (~36), Champion (~45); slight fatigue per rep and
  ±12 % jitter. Default level from MMR (new players → Rookie). Modes: Max reps 60 s, Speed 20, Best of 3 (fixed clock).
- Where they appear: the "Practice vs bot" section of the Battle tab; the quick-match queue offers "Practice vs a bot"
  after 15 s and when the queue times out; a ghost battle with no human run of that mode yet races a bot instead.
- Bots don't count toward the 3-a-day ghost limit (cap: 100 bot battles a day as abuse protection).

## 8. Invites & deep links
- Invite a friend from friends list or battle tab → `battle_invites` row + push notification + Realtime event. Expires after 5 min.
- Share link `https://pushly.app/b/{code}` (Universal Links / App Links) → opens the app into the invite; if the app isn't installed → store page.
