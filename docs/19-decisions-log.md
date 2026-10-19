# 19 — Decisions log (ADR-lite)

Format: `D-xxx — Title — Status (Accepted / Proposed / Superseded) — Date` + context, decision, consequences.
Add a new entry for every new dependency, every change to shared constants, and every spike result.

## Accepted
**D-001 — Native apps on both platforms (Swift + Kotlin), no shared UI/logic framework** — Accepted — 2026-10-19
Founder's choice. Best access to AlarmKit, camera and on-device ML. Cost: logic duplicated → mitigated by shared specs, codegen and test vectors with a CI parity job.

**D-002 — Backend: Supabase (EU region)** — Accepted — 2026-10-19
Postgres + RLS fits leaderboards/clans; Realtime for battles & chat; Edge Functions for authoritative logic; pg_cron for periodic jobs.

**D-003 — English-only UI, localizable from day one** — Accepted — 2026-10-19

**D-004 — iOS minimum iOS 26** — Accepted — 2026-10-19
AlarmKit (alarms that break through Silent mode and Focus) requires iOS 26. Older iOS versions cannot provide a reliable alarm for third-party apps.

**D-005 — Android minSdk 29** — Accepted — 2026-10-19

**D-006 — Pose model: MediaPipe Pose Landmarker on both platforms** — Accepted — 2026-10-19
Same 33-landmark topology on both platforms → one RepEngine spec and shared test vectors. Apple Vision / ML Kit rejected for parity reasons. iOS via SPM (`MediaPipeTasksVision`), CPU-only on iOS — validated in spike P3-01. Licence: Apache 2.0.

**D-007 — Rep counting = deterministic heuristic state machine (v1), learned validator later** — Accepted — 2026-10-19
Explainable, testable, identical across platforms. A learned model is added later only as a second opinion for anti-cheat.

**D-008 — Battle video: LiveKit Cloud (SFU)** — Accepted — 2026-10-19
Swift and Kotlin SDKs, data channels, free Build tier for development; self-hostable (open source) if costs grow. No recording.

**D-009 — Purchases via RevenueCat** — Accepted — 2026-10-19

**D-010 — Ads via AdMob + UMP** — Accepted — 2026-10-19

**D-011 — Global competitive periods in UTC, personal stats in local time** — Accepted — 2026-10-19

**D-013 — iOS "ring until done" via nag chain** — Accepted — 2026-10-19
AlarmKit's alert always has a Stop button, so persistence is emulated with pre-scheduled follow-up alarms + dead-man's switch while the camera is active (doc 04 §5.2).

**D-014 — Leaderboard streak = pure streak (no freezes)** — Accepted — 2026-10-19
Prevents Pro/rewarded-ad freezes from becoming a paid competitive advantage.

**D-015 — Minimum age 16** — Accepted (revisit) — 2026-10-19
Simplest GDPR-safe option with chat, live video with strangers and ads.

**D-016 — Crash reporting Sentry, product analytics PostHog (EU)** — Accepted — 2026-10-19

**D-017 — Display font Barlow Condensed (SIL OFL)** — Accepted — 2026-10-19

## Proposed / to verify
**D-012 — Android exact-alarm permission: `SCHEDULE_EXACT_ALARM` vs `USE_EXACT_ALARM`** — Proposed
Start with `SCHEDULE_EXACT_ALARM` (user-granted). Evaluate `USE_EXACT_ALARM` eligibility under Google Play policy (alarm clock as core functionality) before launch.

**D-018 — Android ring service foreground-service type** — Proposed — to be settled by spike P2-02 (`systemExempted` vs `mediaPlayback`).

**D-019 — iOS AlarmKit limits** — Proposed — spike P2-01 to determine per-app alarm count limit, custom sound limits, behaviour after reboot/update/offload; adjust the rolling window (default 7 days) and nag chain size.

## Open questions (for the founder)
- **Q-01:** Domain — docs assume `pushly.app` for links, legal pages and Universal/App Links. Confirm ownership or pick another domain.
- **Q-02:** Alarm sounds — commission original sounds or buy a licensed pack? (Need ≥ 12 for launch.)
- **Q-03:** Brand colours / logo — doc 14 proposes a palette; confirm or provide brand assets.
- **Q-04:** Pro pricing per region (doc 13 §2 suggested prices).
- **Q-05:** Should knee push-ups exist as an unranked "beginner" option later? (v1: not counted.)
- **Q-06:** Apple Health / Health Connect export of workouts — v1.1?
