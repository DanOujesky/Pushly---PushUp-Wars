# 06 — Anti-cheat

Principle: **defence in depth**. No single check is perfect; the combination makes cheating expensive and visible. The server is the final authority; the client is assumed hostile.

Threats we handle:
| # | Threat | Main defences |
|---|---|---|
| T1 | Half reps / bad form | RepEngine rules (doc 05) |
| T2 | Fake motion (arm waving, head bob, moving the phone) | plank + full-body rules, phone-motion check, consistency rules |
| T3 | Replaying a video on a screen in front of the camera | screen-replay detection, liveness challenges, clip review |
| T4 | Modified app / injected landmarks / fake API calls | App Attest / Play Integrity, signed rep logs, server-side plausibility |
| T5 | Clock tampering (wake challenge) | server time anchors, monotonic clock, ring timestamps |
| T6 | Multi-accounting / win-trading in battles | device binding, match history analysis, rate limits |
| T7 | Farming reps for clan wars | per-day caps, diminishing returns, trust score |
| T8 | Someone else doing the push-ups | accepted risk (we don't do face ID); social reporting in battles |

## 1. Trust score
Each user has `trust_score` 0–100 (start 70). Increased by clean history (+1/week, max 90 without review), long-standing account, verified review clips. Decreased by flags (see §6). Effects:
| Score | Effect |
|---|---|
| ≥ 50 | normal |
| 30–49 | reps count for personal stats; **excluded from public leaderboards** (shown only to self, "shadow" mode), clan war reps ×0.5, ranked battles only vs. other low-trust players |
| < 30 | competitive features disabled pending review; user is informed with an appeal option |

## 2. On-device checks (in `RepEngine` + `Integrity`)
1. **Phone motion:** accelerometer/gyro sampled at 50 Hz during sessions. If device motion RMS > threshold while reps are counted (phone is being moved instead of the body), reps are rejected with `INTEGRITY`. The phone must be still.
2. **Single person:** if MediaPipe detects a second pose candidate (run detection with `numPoses = 2` every 30th frame) with significant presence → pause counting, hint "Only one person in frame".
3. **Frame continuity:** reject sessions with frame timestamp gaps > 400 ms more than 3× per minute (dropped/injected streams), or identical consecutive frames (frozen feed).
4. **Screen-replay heuristics (T3):** (a) luminance flicker spectrum analysis on a downscaled frame every 10th frame (screens show 50/60 Hz banding / moiré patterns with the camera at 30 fps); (b) rectangular bright-border detection around the person; (c) depth plausibility — world-landmark limb lengths must stay stable (±15 %) across the session; flat replays produce unstable z. Each produces a 0–1 suspicion score included in the rep log; **client doesn't block on these alone**, server weighs them.
5. **Liveness prompts (ranked battles + top-100 leaderboard users only):** at random moments the UI shows a prompt such as "Raise your LEFT hand at the top" — the next lockout must include the requested hand lifting (wrist landmark above shoulder for ≥ 300 ms). Failure ×2 → session flagged. A pre-recorded video can't follow random prompts.
6. **Release-build hygiene:** no debug counters, no simulated pose sources; `PoseEngine` only accepts frames from the live camera pipeline object (no file input in release); jailbreak/root detection adds a flag (not a block).

## 3. Signed rep log
Every rep session produces a **rep log** that is uploaded (schema `shared/contracts/rep-log.schema.json`):
```jsonc
{
  "sessionId": "uuid",
  "userId": "uuid",
  "context": { "type": "wake" | "battle" | "training", "occurrenceId": "...", "battleId": "...", "roundIndex": 0 },
  "specVersion": 1, "appVersion": "1.0.0 (42)", "platform": "ios", "deviceModel": "iPhone15,2",
  "timing": {
    "monotonicStartMs": 123456, "wallStart": "2026-10-20T04:30:12.345Z",
    "serverAnchor": { "serverTime": "2026-10-20T04:21:00Z", "monotonicAtAnchorMs": 100000 } | null,
    "ringStartedAtMonotonicMs": 110000 | null
  },
  "reps": [ { "i": 1, "tStartMs": 1200, "tBottomMs": 1650, "tEndMs": 2050, "quality": 88,
              "minElbow": 84, "maxElbow": 168, "minBodyLine": 162, "depth": 0.55 } ],
  "rejected": { "NOT_DEEP_ENOUGH": 2 },
  "featureTrace": "<base64 zstd>",   // downsampled 10 Hz trace of key features (elbow, bodyLine, depth, visibility, device motion) — NOT video
  "suspicion": { "replay": 0.04, "motion": 0.01, "continuity": 0.0, "liveness": "passed" | "failed" | "n/a" },
  "integrity": { "attestationToken": "...", "keyId": "..." },
  "signature": "base64(ECDSA-P256(SHA-256(canonicalJSON(log without signature))))"
}
```
- Keys: iOS **App Attest** key (DeviceCheck) — `attestKey` once per install (registered via Edge Function `register-device`), then `generateAssertion` over the log hash. Android **Play Integrity** standard request with `requestHash = SHA-256(log)` + a Keystore-backed ECDSA key registered at install.
- Server verifies attestation/assertion and signature; failure → session stored but `verified = false` (counts for nothing competitive) and a flag.

## 4. Server-side validation (`submit-rep-session` Edge Function)
Checks in order — any **hard** failure rejects competitive use; **soft** failures add flags:
| Check | Type |
|---|---|
| Signature + attestation valid, key belongs to user's device | hard |
| `specVersion` supported, app version ≥ min supported | hard |
| Rep timing plausible: every rep `450 ms ≤ duration ≤ 8000 ms`; ≥ 3 consecutive reps < 600 ms → soft flag; sustained rate > 1.6 reps/s for > 20 reps → hard | hard/soft |
| Feature trace consistent with reps (elbow minima match `tBottomMs` within 150 ms, count of oscillations = counted + rejected ± 1) | hard |
| Physiological ceilings: > 150 reps in one continuous set, > 1,000 verified reps/day, > 5,000/week → hold for review | soft (hold) |
| Personal-best jump: set max > 1.8× user's previous best (with ≥ 10 sessions history) | soft |
| Suspicion scores: replay > 0.6 or motion > 0.5 | soft (heavy) |
| Wake timing (doc 04): first rep after ring, within deadline, using server anchor when available; if no anchor, wall clock must be within ±2 min of the server receive time minus elapsed monotonic time | hard |
| Duplicate session / replayed log (same sessionId or same signature) | hard |
| Battle: reps only within server-defined round window (doc 07) | hard |

## 5. Late uploads
- Uploaded ≤ 48 h after session end: full validation, counts for everything still open.
- 48 h – 7 days: counts for personal stats & totals only.
- > 7 days: personal stats only, flagged `late`.

## 6. Flags, review & sanctions
- `anti_cheat_flags` table: (user, session, type, severity, details, status). Severity weights reduce `trust_score` (soft 3–10 pts, hard 15–30 pts).
- **Review clips (opt-in, T3/T8):** users in the top 100 of any public leaderboard, or with pending holds, are asked once to enable "Verified athlete": the app records a **3-second, 240p, no-audio clip** around 2 random reps per session, uploads it to private Storage bucket `review-clips` (encrypted at rest, auto-deleted after 30 days, accessible only to moderators). Declining is allowed but such users stay off the public top 100 lists (they still compete in battles normally).
- Moderator tooling (Phase 7): simple internal web page (Supabase Studio views + a small admin Edge Function) to view flags, clips, feature traces; actions: clear flag, void session, adjust trust, suspend.
- Sanctions ladder: warning → leaderboard removal for season → competitive ban 30 days → permanent ban. Trophies gained in voided battles are reverted from both sides (doc 08 §2.4).
- Battle reports: after any battle a player can report "Not real push-ups"; 3+ independent reports on different battles within 14 days → review.

## 7. Win-trading & multi-accounting (T6)
- One account per device for ranked play (device key binding; changing account on the device → ranked cooldown 7 days).
- Friend-ranked battles: max 3 ranked battles per pair per day count for trophies.
- Detect pairs with abnormal repeated matchups + one-sided results → flag both.
