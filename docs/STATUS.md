# Project status

_Last updated: 2026-10-20 — Phase 0 + 1 done; Phase 2 (alarm system) implemented on both platforms + backend, CI green; real-device runs pending._

## Done and verified (tests ran green)
| Area | What | How it was verified |
|---|---|---|
| Repo | monorepo layout, `.gitignore`, `.editorconfig`, `.gitattributes`, git history | — |
| Backend | migrations `0001` extensions/enums, `0002` profiles + devices + signup trigger + `update_profile` + `username_available` + `public_profiles` view, `0003` app_config | 34 DB assertions on Postgres 16 (`tools/db-sandbox/run-tests.sh`), incl. "every table has RLS" guard |
| Backend | Edge Function `health` + shared error helpers | 5 Deno tests, `deno lint`, `deno fmt --check` |
| Shared | design tokens (`tokens.json`) with WCAG contrast check | contrast check + codegen unit tests |
| Shared | code generator → Swift/Kotlin tokens and rep-engine constants, `--check` mode | 6 unit tests; generated files committed |
| Shared | executable reference rules (`tools/reference`): alarm occurrences incl. DST, validation, trophies, leagues, season reset, wake points, clan war caps | 22 hand-written tests with values worked out from the docs |
| Shared | **38 generated test-vector files** in `shared/test-vectors` (30 alarm cases incl. Prague/New York/Lord Howe DST, date line) | `build_vectors.py --check` |

Bug found and fixed while testing: placeholder usernames could collide (now unique with fallback).
Doc fix: light-mode lime `#6FA800` failed 3:1 contrast on white → `#679C00`.

## Verified by GitHub Actions (2026-10-19)
| Workflow | Result |
|---|---|
| `ios.yml` | XcodeGen project generated, app + 3 packages compiled with Swift 6 strict concurrency, all unit tests passed on an iOS 26 simulator (cloud Mac) |
| `android.yml` | Gradle sync, unit tests (`:core:common`, `:engine:rep`, `:app`) passed, debug APK built (downloadable as the `pushly-debug-apk` artifact) |
| `supabase.yml` | migrations + 34 tests on the **real Supabase stack with real pgTAP**, plus db-sandbox and Deno function checks |
| `contracts.yml` | codegen up to date, reference rules + test vectors up to date |

Found by the real Supabase run and fixed: the signup trigger used `gen_random_bytes` (pgcrypto), which Supabase keeps in
schema `extensions`. The local db-sandbox now mirrors that layout.

Failure output of every CI step is published as a GitHub annotation (`tools/ci/run-annotated.sh`), so errors can be
read from the Checks API without raw-log access.

## Phase 1 — implemented and verified by CI (2026-10-19)
| Area | iOS | Android |
|---|---|---|
| Backend client | `Networking` package on supabase-swift | `:core:network` on supabase-kt |
| Session routing (launch → update check → welcome → sign-in → profile setup → tabs, guest mode) | `AppSession` + tests | `AppSession` + tests |
| Sign-in: email link (`pushly://auth-callback`, PKCE) — works on Supabase free tier | ✅ | ✅ |
| Sign-in: email 6-digit code (needs custom SMTP so the email can show the code) | ✅ | ✅ |
| Sign-in with Apple | ✅ (needs Apple + Supabase provider setup to work for real) | n/a |
| Sign-in with Google | ⏳ waits for OAuth client IDs (see "Needs Dan") | ⏳ |
| Profile setup: username with live availability, avatar color, country, birth year 16+ | ✅ | ✅ |
| Profile tab: header, privacy settings (optimistic save), sign out, guest CTA | ✅ | ✅ |
| Force-update screen from `app_config` | ✅ | ✅ |
| Shared rules (username, age gate, version compare) | vectors `account/rules.json` | same vectors |
| Payload fixtures (`profile.json`, `app_config.json`) decoded in tests | ✅ | ✅ |

Server: `update_profile` now also rejects placeholder-shaped usernames (`u_` + 12 hex), matching the shared rules.

Hosted dev project `wuvkxjezqyzxthtezplq` (EU): migrations and auth config deployed by `supabase-deploy.yml`.

What is *not* verified yet: a real sign-in on a phone against the hosted project, UI screenshots/snapshots,
VoiceOver/TalkBack pass, SwiftLint/ktlint in CI.

## Phase 2 — alarm system, implemented and verified by CI (2026-10-20)
| Area | iOS | Android | Backend |
|---|---|---|---|
| Domain: model, validation, occurrences (DST), challenge occurrence, OS alarm plan | `AlarmDomain` — shared vectors | `:core:alarm` — same vectors | validation = same vectors (`031_*`) |
| Local storage (one JSON document, D-035) + outbox + ring state | App Group file | device-protected file (direct boot) | — |
| Scheduler (single owner) | AlarmKit: 7-day window, nag chain, dead-man's switch, snooze, reconcile of stuck alerts, practice alarm — unit tested with a fake AlarmKit | `setAlarmClock` next occurrence, receivers (boot/locked boot/time/zone/update/permission), integrity worker | — |
| Ringing | system alarm UI + Stop / Start push-ups intents, Live Activity, in-app quiet sound while the session is open | foreground ring service, full-screen `RingActivity` (no Stop), hold-3-s give up, snooze in escalation | — |
| Wake tab, editor (modes, per-day times, skip next, pause, sounds, test alarm), wake-session placeholder (debug-only Complete) | ✅ | ✅ | — |
| Health check + banners + evening reminder | ✅ | ✅ | — |
| Permission explainer (never at launch) | ✅ | ✅ | — |
| Sync (outbox upload + restore on a new phone) | ✅ | ✅ | RPC `sync_alarms`, RLS, versions history, 19 + 17 DB tests |

Seen in CI screenshots: iOS Wake tab with alarms, health banner and wake session (simulator). The Android emulator
job (`android-screens`, practice alarm on a locked emulator) is ready but the emulator never finished booting on
GitHub's hosted runners (3 attempts) — it is manual-only until that is solved; Android is verified by build + tests
and on Dan's phone.

Not verified yet (needs real phones): everything in `docs/qa/phase-2-alarm-device-tests.md` — AlarmKit per-app limit,
reboot/update behaviour, OEM battery killers, 30-night run (AT-ALM-10). Not built: overrides calendar, sound import (Q-08).

## Phase 3 — camera, pose & rep engine (2026-10-20)
| Area | iOS | Android | Shared |
|---|---|---|---|
| RepEngine (smoothing, features, placement, state machine, evaluation, quality) | `RepEngine` package | `:engine:rep` | reference `pushly_ref/rep_engine.py` (D-040) |
| Test vectors | all pass, event-by-event parity | all pass, same | 25 synthetic vectors (good reps, every form error, 9 cheat types) + importer for real recordings |
| Camera + MediaPipe pose (D-039): front camera 720p, upright un-mirrored frames, low-light check, pre-warm, lite model on heat | `PoseEngine` (AVFoundation) | `:engine:pose` (CameraX) | models in `shared/pose-models` |
| Session UI: counter, skeleton overlay, hints (rate-limited + tips), guidance, haptics, voice counting, camera explainer | `WakeFlowFeature` | `:feature:wakeflow` | — |
| Wake challenge uses the camera (target reps → alarm done) | ✅ | ✅ | — |
| Free training + summary (PS-80, local only) | ✅ | ✅ | — |
| Pose recorder (debug only) + `tools/pose-recorder/import.py` (D-041) | ✅ | ✅ | ✅ |

Verified by CI: engines + vectors + session models on both platforms, both apps build with MediaPipe linked.
Not verified yet (needs a real phone and real people): counting accuracy on real bodies, fps / latency / battery
(P3-01 spike), camera orientation on every device — checklist `docs/qa/phase-3-camera-device-tests.md`.
Not built yet: placement guide screen + calibration flow (PS-04, doc 05 §6) — sessions start directly with live
guidance; anti-cheat beyond device motion (liveness, screen replay, two people — doc 06, Phase 7 hooks).

## Phase 4 — Wake Challenge end to end (2026-10-20)
| Area | iOS | Android | Backend |
|---|---|---|---|
| Rules: day plan (15-min snapshot), 5 modes, points, streaks (personal + pure, freezes, pause cap) | `WakeRules` (provisional) | `WakeRules` (provisional) | SQL = authority (D-043); all three pass `shared/test-vectors/wake` |
| Schema: wake attempts, streaks, rep sessions + logs, UTC/local stats, personal records, flags | — | — | migration 0007 + 0008, RLS, 29 + 69 DB tests |
| `submit-rep-session`: shape + plausibility checks, server-time conversion, idempotent apply | — | — | Edge Function (D-044), vectors `rep-log`, deployed |
| Wake flow: all 5 modes live (sprint 3-2-1, sets + rest re-ring, beat the clock, escalation), give up, deadline | `WakeChallengeModel` | `WakeChallenge` | — |
| Result screens (beaten / lost, pending → server points + streak) | ✅ | ✅ | — |
| Rep-log outbox (offline, retries, results kept) + training uploads | `SessionUploader` | `SessionUploader` | — |
| Wake tab: 🔥 streak, this-week strip, push-ups today, pending marker | ✅ | ✅ | `get_wake_summary` |

Not done yet: P4-02 part 2 — App Attest / Play Integrity attestation (logs are already signed with a per-install
device key, D-047),
screen flicker / border replay heuristics (need device data). Done since: second-person pause, feed continuity,
limb-length replay signal and the server-checked 10 Hz feature trace (D-046).
Device checklist: `docs/qa/phase-4-wake-challenge-tests.md`.

## Phase 5 — stats, progress, achievements (2026-10-21)
| Area | iOS | Android | Backend |
|---|---|---|---|
| XP (1 / rep, +20 / wake), levels, 44 achievements, streak-freeze rewards | — | — | migration 0010 (D-048), 23 + 27 DB tests, vectors `progress` ✅ local |
| `get_stats(period)` (KPIs + Δ, daily, cumulative, wake times, heatmap, records) + `get_achievements()` | — | — | ✅ local, not deployed yet |
| Stats screen: level card, period picker, KPI tiles, charts 1–4 + 6 with scrubbing, records | `StatsFeature` (Swift Charts) | `:feature:stats` (Canvas, D-049) | — |
| Achievements screen, rewards on result screens (XP, level up, new best set, unlocked) | ✅ | ✅ | — |

✅ Client code compiled and tested by CI on 2026-10-21 (after the repo went public). Not built yet: chart 5 (form multi-line needs depth / body-line per day),
chart 7 (battles, Phase 7), share cards and confetti (P5-05 rest).

## Phase 6 — social, leaderboards, notifications (2026-10-21)
| Area | iOS | Android | Backend |
|---|---|---|---|
| Friends: search, requests, accept/decline, remove, block, share link | `SocialFeature` FriendsView | `:feature:social` | 0011, 35 DB tests ✅ local |
| Activity feed (wake beaten, achievements, level up, best set) + kudos 👊 | ✅ | ✅ | triggers + `get_friend_feed` / `give_kudos` |
| Ranks tab: wake / streak / push-ups × global / country / friends × periods, own row pinned, anonymous + shadow | `RanksView` | `RanksScreen` | snapshots + `get_leaderboard`, 22 DB tests ✅ local |
| Push pipeline: prefs, quiet hours, caps, collapse, APNs + FCM sender, cron | — (client P6-06 open) | — | 0011–0013 + `push-send`, 11 DB + 7 deno tests ✅ local |

✅ CI green 2026-10-21. Not built: QR code, friend profile screen, push registration in
the apps (P6-06), widgets (P6-07).

## Phases 7–10 — battles, clans, compliance, Pro (2026-10-21)
| Area | iOS | Android | Backend |
|---|---|---|---|
| Battles: invites, ready → countdown → live, rep events, settlement, trophies + Glicko-2 MMR, matchmaking, seasons | `BattleFeature` (no video yet, D-055) | `:feature:battle` | 0014 + `battle-token`, 41 + 142 DB tests ✅ local |
| Clans: create/join/requests, roles, chat, weekly wars with caps, clans board | `ClanFeature` | `:feature:clan` | 0015, 42 + 42 DB tests ✅ local |
| Reports, account deletion (fresh sign-in), data export, notification prefs | Account & data screen | Account & data screen | 0016, 19 DB tests ✅ local |
| Pro entitlements (RevenueCat webhook), monthly Pro freezes | — (SDK later) | — | 0016 + `revenuecat-webhook` ✅ local |
| AdsGate (where ads may appear) | `Core/AdsGate` + vectors | `:core:common` AdsGate + vectors | reference `ads.py`, vectors `ads/gate.json` |

✅ CI green for both apps and migrations 0010–0018 deployed on 2026-10-21 (device testing still open). Not built yet: LiveKit video, Realtime
broadcasts, ghost battles, best-of-3 / turns HUDs, clan war history + chests, push registration in the apps, widgets,
AdMob + UMP, RevenueCat SDK + paywall. Legal pages done 2026-10-21 (D-056; GitHub Pages must be switched on once).

## Roadmap progress (Phase 0)
- [x] P0-01 Monorepo scaffold
- [x] P0-02 iOS project (SwiftLint runs locally only — not yet in CI)
- [~] P0-03 Android project — builds and tests in CI; ktlint, detekt and Hilt still to add
- [x] P0-04 Supabase local (config, migrations, seed, tests, function tooling)
- [x] P0-05 Codegen — tokens + rep-engine spec done; JSON-Schema → models comes with the first contract (P2-09)
- [x] P0-06 CI — all four workflows green
- [x] P0-07 Core module (feature-flag reader comes with P1-07 client part)
- [x] P0-08 App shell + deep-link parser
- Ahead of schedule (backend only, verified): P1-03 profiles & devices, P1-07 `app_config` table; P1-01 design tokens (data part)
- Ahead of schedule (shared, verified): reference rules + test vectors for P2-03, P7-02, P8-03

## Roadmap progress (Phase 1)
- [x] P1-01 Design tokens + "dark arena" design (D-033/D-034): Barlow Condensed + Figtree bundled, new components, restyled launch / welcome / sign-in / profile setup / profile / update screens, app icons on both platforms. iOS verified visually via CI simulator screenshots (branch `ci-screenshots`); Android verified by build + tests, visual check on Dan's phone.
- [~] P1-02 Components — buttons, text field, card, banner, avatar done; the rest of doc 14 §4 comes with the screens that need them
- [x] P1-03 Profiles & devices (backend)
- [~] P1-04 Auth — email code + Apple done; Google pending client IDs
- [x] P1-05 Onboarding UI
- [x] P1-06 Profile screen shell & settings
- [x] P1-07 Remote config + force update

## Needs Dan
- Phase 3 on your phone: `docs/qa/phase-3-camera-device-tests.md` (free training, wake challenge, fps notes), then
  record real sets with the Pose recorder (`docs/qa/pose-recording.md`) — friends and family count too (≥ 30 people).
- Try the app: Android — download the `pushly-debug-apk` artifact from the latest `android` run and install it; iOS — TestFlight once the secrets from `docs/RELEASING.md` are added (store apps `app.pushly` created 2026-10-20).
- Test sign-in on a phone: install the `pushly-debug-apk` artifact, sign in with **your own email** (Supabase's built-in
  mailer only delivers to project team members), tap the link in the email on the same phone.
- Before beta: custom SMTP in Supabase (e.g. Resend + your domain) → then re-enable the code email template (D-032).
- Apple sign-in: enable the Apple provider in Supabase with your Services ID / key from the Apple Developer account.
- Google sign-in (later): OAuth client IDs (web + iOS + Android) in Google Cloud.
- Decisions in `docs/19-decisions-log.md` → Open questions (domain, sounds, brand, pricing).
- Apple Team ID in `ios/Config/Secrets.xcconfig` (local) / CI secrets.

## Founder setup done (2026-10-22)
Dan finished the account/secret setup: GitHub Pages on, APNs key + Supabase secrets, Vault entries for the push cron,
Firebase project (google-services.json secret, FCM service account), LiveKit Cloud keys, Apple + Google providers in
Supabase, Google OAuth clients (web, iOS, Android with the Play signing SHA-1s), Play Integrity linked. Still open on
purpose: AdMob and RevenueCat (wait for the business registration, Q-10). Next: device testing via TestFlight
(iPhone first), then LiveKit video in battles.
