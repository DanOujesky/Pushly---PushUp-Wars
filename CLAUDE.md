# CLAUDE.md — Pushly: PushUp Wars

This file is the **contract** for every Claude Code session working in this repository.
Read it fully before writing any code. When this file and a doc in `docs/` disagree, **this file wins**;
when two docs disagree, the more specific doc wins and you must flag the conflict in `docs/19-decisions-log.md`.

---

## 1. What we are building (one paragraph)

Pushly is a free mobile fitness game for **iOS (Swift / SwiftUI)** and **Android (Kotlin / Jetpack Compose)**,
both built **natively and in parallel**, backed by **Supabase**. Users join a **Wake-Up Challenge**: a fully
configurable alarm that only counts as "beaten" when the user does a set number of push-ups verified by
**on-device AI pose detection** through the camera. On top of that: real-time **1v1 push-up battles** with
split-screen video, **trophies/ranks**, **global and friends leaderboards**, **clans** with weekly **Clan Wars**,
and beautiful **stats & progress** charts. Monetization: ads at first, later a **Pushly Pro** membership that
removes ads and adds cosmetic/comfort extras. **Never pay-to-win.** UI language: **English only**.

Bundle / application ID: **`app.pushly`** (iOS bundle ID already registered in App Store Connect).

---

## 2. Reading order

1. `docs/README.md` — index of all docs
2. `docs/01-product-vision.md` → `docs/02-product-spec.md` — what and why
3. `docs/03-architecture.md` — how the pieces fit
4. The feature doc for the area you are touching (04–16)
5. `docs/17-roadmap.md` — **which phase/task you are on**. Never build ahead of the current phase.
6. `docs/18-testing-qa.md` — what "done" means
7. `docs/19-decisions-log.md` — decisions already made (do not re-litigate them silently)

---

## 3. Repository layout (monorepo)

```
pushly/
├── CLAUDE.md
├── docs/                      # specs — source of truth for behaviour
├── shared/
│   ├── contracts/             # JSON Schemas for every payload crossing a boundary (API, realtime, rep logs)
│   ├── rep-engine-spec/       # platform-agnostic rep counting spec + constants (YAML)
│   ├── test-vectors/          # golden pose sequences (JSON) — BOTH platforms must pass them
│   └── design-tokens/         # tokens.json → generated Swift + Kotlin (colors, type, spacing, radii, motion)
├── ios/                       # Xcode project "Pushly" (SwiftUI, Swift 6, SPM only)
├── android/                   # Gradle project (Kotlin, Compose, version catalogs)
├── supabase/
│   ├── migrations/            # SQL migrations — the ONLY way schema changes
│   ├── functions/             # Edge Functions (Deno + TypeScript)
│   ├── seed.sql
│   └── tests/                 # pgTAP tests for RLS + SQL functions
├── tools/
│   ├── codegen/               # tokens.json → Swift/Kotlin, JSON Schema → Swift/Kotlin models
│   └── pose-recorder/         # dev tool to record landmark sequences into test-vectors
└── .github/workflows/         # CI: ios, android, supabase, contracts
```

---

## 4. Non-negotiable rules

### 4.1 Parity
- Every user-facing feature ships on **both** platforms in the same phase. A task is not done until it works on iOS **and** Android (unless the task says "platform: X only").
- Shared behaviour (rep counting, scoring, ranking math, alarm rules) is defined **once** in `shared/` or `docs/` and implemented twice. Both implementations must pass the **same** test vectors.
- If you change a rule on one platform, change it on the other in the same PR, or open a parity task in the roadmap.

### 4.2 Server is the authority
- The client **never** decides trophies, leaderboard positions, clan war results, streaks, or challenge success. Clients submit **signed rep logs**; Edge Functions / SQL functions validate and write results.
- All writes to competitive tables go through Edge Functions or `SECURITY DEFINER` RPCs. Clients have **no direct INSERT/UPDATE** on: `rep_sessions`, `battles`, `trophy_ledger`, `leaderboard_*`, `clan_war_*`, `streaks`, `user_stats_daily`.
- Every table has **RLS enabled**. No exceptions. A migration without RLS policies fails review.

### 4.3 Privacy
- Camera video is processed **on device**. Raw video is **never** uploaded, except short low-res anti-cheat clips described in `docs/06-anti-cheat.md`, and only with the user's explicit consent.
- Battle video goes peer-to-SFU (LiveKit) live only and is **never recorded**.
- No ads, no analytics SDK calls, and no network calls that are not strictly needed during the alarm / wake flow.

### 4.4 The alarm must never fail silently
- Alarm reliability beats every other concern. Any code path that can leave a user without a ringing alarm (permission revoked, schedule not written, OS killed app) must surface a visible warning in-app and on the Alarm screen.
- Alarms are scheduled **locally** from the locally stored schedule. They must work **offline** and without a logged-in session. Sync to server is for leaderboard/streak only.

### 4.5 Ads
- Never show any ad: during the wake flow, during camera sessions, during battles, on the alarm editor, or within 10 minutes after a wake challenge ends. See `docs/13-monetization.md` for exact placements and frequency caps.

### 4.6 Code quality
- No force unwraps (`!`) or `try!` in Swift production code (allowed in tests only); no `!!` in Kotlin production code.
- No `print` / `Log.d` left in production paths — use the logging wrapper (`PLog` on both platforms).
- No new third-party dependency without adding it to `docs/19-decisions-log.md` with reason + licence.
- No hard-coded strings in UI: iOS uses String Catalogs (`Localizable.xcstrings`), Android uses `strings.xml`. English only for now, but keep it localizable.
- No hard-coded colors / font sizes: use generated design tokens only.
- Secrets never in the repo. Use `.xcconfig` (gitignored) on iOS, `local.properties` / Gradle secrets on Android, Supabase secrets for functions.

---

## 5. Tech stack (fixed — do not swap without a decision-log entry)

| Layer | iOS | Android |
|---|---|---|
| Language | Swift 6 (strict concurrency) | Kotlin 2.x |
| UI | SwiftUI | Jetpack Compose + Material 3 (custom themed) |
| Min OS | **iOS 26** (required by AlarmKit) | **minSdk 29** (Android 10), target/compile = latest stable |
| Architecture | MVVM + `@Observable` view models, feature modules as local SPM packages | MVVM + UDF (StateFlow), multi-module Gradle |
| DI | Simple container (protocol + init injection) | Hilt |
| Async | async/await, AsyncStream | Coroutines, Flow |
| Persistence (local) | SwiftData | Room |
| Camera | AVFoundation (`AVCaptureSession`) | CameraX |
| Pose model | **MediaPipe Pose Landmarker** (`MediaPipeTasksVision` via SPM) | **MediaPipe Pose Landmarker** (`com.google.mediapipe:tasks-vision`) |
| Alarm | **AlarmKit** (+ App Intents, Live Activity widget extension) | `AlarmManager.setAlarmClock()` + foreground service + full-screen intent |
| Charts | Swift Charts | Vico (Compose charts) |
| Realtime video | LiveKit Swift SDK | LiveKit Android SDK |
| Backend client | `supabase-swift` | `supabase-kt` |
| Purchases | RevenueCat (StoreKit 2) | RevenueCat (Play Billing) |
| Ads | Google Mobile Ads (AdMob) + UMP consent | Google Mobile Ads (AdMob) + UMP consent |
| Push | APNs via Supabase Edge Function | FCM via Supabase Edge Function |
| Device integrity | App Attest | Play Integrity API |
| Crash / analytics | Sentry (crashes) + PostHog (product analytics, EU host) | same |

Backend: Supabase (Postgres 15+, Auth, Realtime, Storage, Edge Functions in Deno/TypeScript, `pg_cron`).

---

## 6. Naming & conventions

- Domain names are identical across platforms and backend: `WakeChallenge`, `AlarmSchedule`, `RepSession`, `RepEvent`, `Battle`, `BattleMode`, `Clan`, `ClanWar`, `TrophyLedgerEntry`, `League`, `Streak`.
- Database: `snake_case`, plural table names, `uuid` PKs (`gen_random_uuid()`), `created_at timestamptz default now()`.
- All timestamps stored in **UTC**. Each user has `timezone` (IANA).
  - **Personal** things (wake attempts, streaks, personal stats, "today" on the Wake tab) use the user's **local** day.
  - **Global competitive periods** (leaderboard day/week/month, Clan War week, seasons) use **UTC**: day = 00:00–24:00 UTC, week = Monday 00:00 UTC → next Monday 00:00 UTC, season = calendar month UTC. See docs 08 and 09.
- Swift: types `UpperCamelCase`, files named after the main type. Kotlin: same.
- Feature module names: `AlarmFeature`, `WakeFlowFeature`, `PoseEngine`, `RepEngine`, `BattleFeature`, `ClanFeature`, `LeaderboardFeature`, `StatsFeature`, `ProfileFeature`, `ShopFeature`, `OnboardingFeature`, `DesignSystem`, `Networking`, `Persistence`.

---

## 7. Workflow for every task

1. Find the task in `docs/17-roadmap.md`. Restate its acceptance criteria before coding.
2. Read the relevant feature doc(s). If something is ambiguous, **do not invent product behaviour**: pick the most conservative option, implement it, and add an entry under "Open questions" in `docs/19-decisions-log.md`.
3. Contracts first: if the task crosses a boundary, update `shared/contracts/*.schema.json` first, regenerate models, then implement.
4. Backend second (migration + RLS + pgTAP tests + Edge Function + its tests), then iOS, then Android (or both in parallel), each with tests.
5. Run all checks (§8). Fix everything.
6. Update docs if behaviour changed. Tick the task in the roadmap.
7. Commit using Conventional Commits: `feat(alarm): ...`, `fix(rep-engine): ...`, `chore(ci): ...`. One logical change per commit.

---

## 8. Definition of done (every task)

- [ ] Builds with zero warnings on iOS (Xcode, Swift 6 strict concurrency) and Android (`./gradlew build`, warnings as errors in our modules).
- [ ] Unit tests added/updated; all pass: `xcodebuild test`, `./gradlew test`, `supabase test db`, `deno test` for functions.
- [ ] Rep-engine changes pass **all** test vectors on both platforms.
- [ ] Lint clean: SwiftLint + swift-format; ktlint + detekt; `deno lint` + `deno fmt --check`.
- [ ] New tables: RLS enabled + policies + pgTAP tests proving a user cannot read/write others' private rows.
- [ ] UI: works in light and dark mode, Dynamic Type / font scale up to 200 %, VoiceOver/TalkBack labels on interactive elements, 44 pt / 48 dp minimum touch targets.
- [ ] No ads in forbidden contexts (§4.5).
- [ ] Docs + roadmap updated.

---

## 9. Commands

```bash
# Backend
supabase start                       # local stack
supabase db reset                    # apply migrations + seed
supabase test db                     # pgTAP
cd supabase/functions && deno test -A

# Codegen (run after editing shared/)
./tools/codegen/run.sh               # tokens + contract models for both platforms

# iOS
cd ios && xcodebuild -scheme Pushly -destination 'platform=iOS Simulator,name=iPhone 17' test

# Android
cd android && ./gradlew ktlintCheck detekt test assembleDebug
```

(If a command does not exist yet, creating it is part of Phase 0 — see roadmap.)

---

## 10. Things you must NOT do

- Do not use cross-platform frameworks (Flutter, React Native, KMP UI). Kotlin Multiplatform is also **not** used — logic is duplicated deliberately and kept in sync by shared specs + test vectors.
- Do not put competitive logic (trophy math, rep validation) only in the client.
- Do not store raw video, face data, or biometric templates on the server.
- Do not request permissions at app launch. Request each permission in context with a pre-permission explainer screen (see `docs/02-product-spec.md` §Onboarding).
- Do not call AlarmKit / AlarmManager from anywhere except `AlarmScheduler` (single owner of alarm state).
- Do not bypass `RepEngine` to count reps (e.g. "tap to count" debug paths must be compiled out of release builds).
- Do not introduce loot boxes, gambling mechanics, or paid advantages in battles/rank.
