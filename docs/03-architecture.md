# 03 — Architecture

## 1. System overview

```
┌──────────────────────────── Device (iOS / Android) ────────────────────────────┐
│                                                                                │
│  UI (SwiftUI / Compose)  ──►  ViewModels  ──►  Use cases / Services            │
│                                                   │                            │
│   ┌──────────────┐  ┌──────────────┐  ┌───────────┴──┐  ┌──────────────────┐   │
│   │ AlarmScheduler│  │ CameraSource │  │ PoseEngine   │  │ RepEngine         │   │
│   │ (AlarmKit /   │  │ (AVFoundation│─►│ (MediaPipe   │─►│ (state machine,   │   │
│   │  AlarmManager)│  │  / CameraX)  │  │  Pose Lmk.)  │  │  form checks)     │   │
│   └──────┬───────┘  └──────────────┘  └──────────────┘  └────────┬─────────┘   │
│          │                                                        │ RepEvents   │
│   ┌──────▼──────────────────────────────────────────────────────▼─────────┐   │
│   │ Local store (SwiftData / Room): alarms, sessions, signed rep logs,     │   │
│   │ outbox queue, cached profile/leaderboards                              │   │
│   └──────────────────────────────┬─────────────────────────────────────────┘   │
│                                  │ SyncEngine (outbox, retry, backoff)          │
└──────────────────────────────────┼─────────────────────────────────────────────┘
                                   │ HTTPS (supabase-swift / supabase-kt)
┌──────────────────────────────────▼──────────── Supabase ───────────────────────┐
│ Auth  │ Postgres (+RLS, pg_cron) │ Edge Functions (Deno) │ Realtime │ Storage   │
└───────┴──────────────────────────┴───────────┬───────────┴──────────┴──────────┘
                                               │ server SDK (token minting)
                                     ┌─────────▼─────────┐
                                     │ LiveKit Cloud (SFU)│  ← battle video only
                                     └────────────────────┘
External: RevenueCat (entitlements → webhook → Edge Function), AdMob, APNs/FCM,
          App Attest / Play Integrity verification, Sentry, PostHog (EU).
```

## 2. Responsibilities

| Concern | Client | Server |
|---|---|---|
| Scheduling & ringing alarms | ✅ owns it, offline | stores a copy of the schedule for sync/restore and for "counts for challenge" rules |
| Counting reps | ✅ real-time on device | re-validates rep logs (plausibility, signatures, timing) |
| Wake challenge success / streak | shows provisional result | ✅ authoritative |
| Battle state | renders, sends rep events | ✅ referee: start time, end, winner, trophies |
| Leaderboards | reads | ✅ computes (materialised tables) |
| Clan war scores | reads (realtime) | ✅ computes |
| Entitlements (Pro) | reads RevenueCat SDK for UI | ✅ webhook → `entitlements` table (used for server-side perks) |

## 3. Client module structure

Identical module names on both platforms.

```
App (composition root, navigation, DI wiring)
├── DesignSystem      tokens, components, charts styling, haptics, sounds
├── Core              PLog, Result types, clock abstraction (Clock for tests), feature flags
├── Networking        Supabase client, auth session, typed API from shared/contracts, SyncEngine
├── Persistence       SwiftData / Room models, repositories, outbox
├── Integrity         App Attest / Play Integrity, rep-log signing (doc 06)
├── Camera            CameraSource (frames, orientation, fps control)
├── PoseEngine        MediaPipe wrapper → PoseFrame (normalised landmarks + visibility)
├── RepEngine         pure logic: PoseFrame stream → RepEvent stream (NO platform imports)
├── AlarmFeature      alarm editor UI + AlarmScheduler (single owner of OS alarms)
├── WakeFlowFeature   ring screen, wake camera screen, results
├── TrainingFeature   free training
├── BattleFeature     matchmaking, lobby, LiveKit room, battle UI
├── LeaderboardFeature
├── ClanFeature       clan home, war, chat
├── StatsFeature      dashboards & charts
├── ProfileFeature    profile, friends, settings, achievements
├── ShopFeature       Pro paywall (RevenueCat), ads wrapper (AdsGate)
└── OnboardingFeature
```

Rules:
- `RepEngine` is **pure** (no camera, no UI, no OS APIs) so it can be unit-tested with test vectors on both platforms.
- Features depend on `Core`, `DesignSystem`, `Networking`, `Persistence`; features **never** depend on each other directly — cross-feature navigation goes through the App's router.
- `AdsGate` is the only place that may show an ad; it checks context rules (doc 13).

### iOS specifics
- Xcode project with app target + **Widget Extension** (AlarmKit Live Activity / countdown UI) + **App Intents** in the app target (alarm buttons) + optional Notification Service Extension (rich push).
- Local SPM packages under `ios/Packages/` (one per module above).
- App Group `group.app.pushly` shared between app and widget extension (next alarm, streak for widgets).
- Home-screen & Lock Screen widgets: "Next alarm + streak" (Phase 6).

### Android specifics
- Gradle multi-module: `:app`, `:core:*`, `:feature:*`, `:engine:pose`, `:engine:rep`.
- `AlarmReceiver` (BroadcastReceiver) → `AlarmRingService` (foreground service) → `RingActivity` (full-screen, shows over lock screen).
- `BootReceiver` + `TimeChangeReceiver` + `PackageReplacedReceiver` re-schedule alarms.
- Glance widgets for "Next alarm + streak" (Phase 6).

## 4. Data flow: a wake-up, end to end

1. `AlarmScheduler` registered the occurrence with the OS (AlarmKit / `setAlarmClock`). Occurrence ID = `alarmId + localDate`.
2. OS fires. User taps **Start push-ups** → app opens `WakeCameraScreen` with `occurrenceId`.
3. `CameraSource` → `PoseEngine` → `RepEngine` produce `RepEvent`s (each with timestamp, quality metrics).
4. `WakeSessionController` applies the mode rules (doc 04 §3), stops the alarm when done, writes a `RepSession` + **signed rep log** to the local store and the outbox.
5. `SyncEngine` uploads to Edge Function `submit-rep-session` with an integrity token.
6. Server validates (doc 06), writes `rep_sessions`, updates `wake_attempts`, `streaks`, `user_stats_daily`, clan war tally; returns the authoritative result.
7. Client replaces "pending" values with server values (PS-90).

## 5. Offline & sync

- Outbox pattern: every server-bound mutation is a row in `outbox` (id, type, payload, created_at, attempts, next_attempt_at). Retries: exponential backoff 5 s → 15 min, forever until success or a non-retryable 4xx.
- Rep sessions older than **48 h** at upload time are accepted for totals/stats but **not** for wake streak or leaderboards of already-closed periods (doc 06 §5).
- Reads are cache-first with stale-while-revalidate; leaderboards cache 60 s.

## 6. Environments

| Env | Supabase project | LiveKit | RevenueCat | Ads |
|---|---|---|---|---|
| `local` | `supabase start` | LiveKit dev server (Docker) | sandbox | test ad unit IDs |
| `staging` | `pushly-staging` | LiveKit Cloud project "staging" | sandbox | test ad unit IDs |
| `prod` | `pushly-prod` (EU region — Frankfurt) | LiveKit Cloud "prod" | production | real IDs |

Build configs: iOS schemes `Pushly-Debug`, `Pushly-Staging`, `Pushly-Release` with `.xcconfig`; Android build types `debug`, `staging`, `release`.

## 7. Feature flags & remote config
Table `app_config` (key, value jsonb, min_app_version) read on launch and cached. Used for: kill-switches (battles, clan chat, ads), rep-engine threshold overrides (only within the safe bounds defined in `shared/rep-engine-spec`), minimum supported app version (force-update screen).

## 8. Observability
- Sentry for crashes + performance traces (`camera_first_frame_ms`, `alarm_ring_to_camera_ms`, `battle_join_ms`).
- PostHog events (EU cloud), names `snake_case`, defined in `shared/contracts/analytics-events.md`. **No events during the wake flow until the session ends** (then one batched `wake_session_completed`).
- Server: Edge Function logs + a `audit_log` table for competitive decisions (trophy changes, anti-cheat flags).
