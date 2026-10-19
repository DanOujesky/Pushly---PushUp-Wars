# 17 — Roadmap (build order)

Rules:
- Work **phase by phase, task by task**. Don't start a task whose dependencies aren't done.
- Every task follows CLAUDE.md §7 (workflow) and §8 (definition of done) and ships on **both** platforms unless marked `[iOS]`, `[Android]` or `[BE]` (backend only).
- **Spikes** are time-boxed experiments; their output is a short report appended to `docs/19-decisions-log.md` and possibly doc updates. Spikes can produce throwaway code in `spikes/` (never merged into app modules).
- Tick tasks `[x]` here when done; `[~]` = written but not yet verified by a real build. `docs/STATUS.md` has the details.

---

## Phase 0 — Foundations
- [x] **P0-01 Monorepo scaffold** — folders per CLAUDE.md §3, `.gitignore`, `README.md` (dev setup), `.editorconfig`, licence placeholder.
- [~] **P0-02 iOS project** — Xcode project `Pushly`, bundle id `app.pushly`, iOS 26 deployment target, Swift 6 strict concurrency, schemes Debug/Staging/Release with `.xcconfig`, local SPM packages for every module in doc 03 §3 (empty), SwiftLint + swift-format, App Group `group.app.pushly`, Widget Extension target (empty).
- [~] **P0-03 Android project** — Gradle Kotlin DSL, version catalog, modules per doc 03 §3, `applicationId app.pushly`, minSdk 29, Compose + Material 3, Hilt, ktlint + detekt, build types debug/staging/release.
- [x] **P0-04 Supabase local** — `supabase init`, config, migration `0001_extensions_enums`, seed, pgTAP set-up, `deno` tooling for functions with a hello function + test.
- [x] **P0-05 Codegen** — `tools/codegen/run.sh`: design tokens → Swift/Kotlin; JSON Schemas → Swift `Codable` / Kotlin `@Serializable`; rep-engine YAML → constants. CI check that generated files are up to date.
- [~] **P0-06 CI** — GitHub Actions: `ios.yml` (build+test on macOS runner), `android.yml`, `supabase.yml` (db reset + pgTAP + deno test), `contracts.yml` (schema lint + codegen diff). Required on PRs.
- [~] **P0-07 Core module** — `PLog`, `Clock` abstraction (injectable), `AppError`, feature-flag reader, build config access — both platforms.
- [~] **P0-08 App shell** — 5-tab navigation (doc 02 §1) with placeholder screens, router, deep-link parser (doc 15 §3) with unit tests.
**Exit:** both apps launch to the tab bar; CI green on all 4 workflows.

## Phase 1 — Design system, auth, profile
- [ ] **P1-01 Design tokens** — `tokens.json` with all values from doc 14; generated themes; light/dark; contrast check script.
- [ ] **P1-02 Components** — all components in doc 14 §4 except charts, with SwiftUI previews / Compose previews and snapshot tests.
- [ ] **P1-03 [BE] Profiles & devices** — migrations `0002`, RLS, `update_profile`, signup trigger creating `profiles`, pgTAP tests.
- [ ] **P1-04 Auth** — Sign in with Apple (iOS), Google (both), email OTP (both) via Supabase Auth; session persistence; sign-out; guest mode flag.
- [ ] **P1-05 Onboarding UI** — PS-01 to PS-03 (value screens, sign-in, profile setup with username availability check, avatar presets, country, age gate 16+).
- [ ] **P1-06 Profile screen shell & settings** — PS-73 structure (privacy toggles functional; other items stubbed).
- [ ] **P1-07 Remote config** — `app_config` table + client reader + force-update screen.
**Exit:** a new user can sign up on either platform, set a profile, see it after reinstall.

## Phase 2 — Alarm system (no camera yet)
- [ ] **P2-01 SPIKE [iOS] AlarmKit** — verify: per-app alarm limit, fixed-date one-shot alarms, custom sound length/format limit, stop/secondary intents behaviour (incl. the bottom-edge dismissal quirk), reboot, app update, offload, Live Activity countdown. Report → decisions log; adjust doc 04 §5.
- [ ] **P2-02 SPIKE [Android] ringing** — `setAlarmClock`, FGS type (`systemExempted` vs `mediaPlayback`) on Android 14/15/16, full-screen intent on locked screen, direct boot re-arm, OEM tests (Samsung, Xiaomi, Pixel). Report → decisions log.
- [ ] **P2-03 Alarm domain** — `AlarmSchedule` model + validation (doc 04 §2), pure `occurrences()` and `challengeOccurrence()` + **alarm-occurrence test vectors** (≥ 25 incl. DST cases) passing on both.
- [ ] **P2-04 Local persistence** — SwiftData/Room models for alarms, outbox.
- [ ] **P2-05 AlarmScheduler** — iOS (rolling window, nag chain API, reconcile) and Android (next-occurrence, receivers, integrity worker) per doc 04 §5–6; idempotent `sync` with unit tests.
- [ ] **P2-06 Alarm editor UI** — PS-20…PS-26: list, create/edit, per-weekday times grid, overrides calendar, skip next, pause, modes picker with validation, sounds (bundled + import), test alarm.
- [ ] **P2-07 Ring experience** — iOS AlarmKit presentation + intents + Live Activity; Android `AlarmRingService` + `RingActivity`. "Start push-ups" opens a placeholder wake screen (debug-only "Complete" button compiled out of release).
- [ ] **P2-08 Alarm health check** — doc 04 §8 pure function + banners + evening local notification.
- [ ] **P2-09 [BE] Alarm sync** — `alarm_schedules` + versions migration, RLS, `sync-alarms` function, client sync via outbox.
- [ ] **P2-10 Permissions explainers** — pre-permission screens for AlarmKit / exact alarm / FSI / notifications / battery.
**Exit:** acceptance tests AT-ALM-01…09 pass (doc 04 §10) on QA devices; AT-ALM-10 (30 nights) starts running in the background of later phases.

## Phase 3 — Camera, pose & rep engine
- [ ] **P3-01 SPIKE pose performance** — MediaPipe full vs lite fps & latency on the device matrix (doc 18 §3); camera sharing approach for later LiveKit use. Report.
- [ ] **P3-02 CameraSource** — doc 05 §2 both platforms, orientation, latest-frame strategy, low-light detection.
- [ ] **P3-03 PoseEngine** — MediaPipe wrapper → `PoseFrame`, model selection, pre-warm, thermal handling.
- [ ] **P3-04 Pose recorder tool** — debug-only screen recording `PoseFrame` JSON for test vectors (doc 05 §8).
- [ ] **P3-05 Test vector collection** — ≥ 200 labelled vectors incl. all cheat types (human task with tool support; Claude prepares checklists & scripts).
- [ ] **P3-06 RepEngine** — smoother, features, placement detector, state machine, evaluation, hints — **pure**, constants from YAML; passes **all** vectors on both platforms; cross-platform parity test in CI (both engines' outputs compared).
- [ ] **P3-07 Camera session UI** — counter, body frame overlay, hints, haptics/sounds, speech counting (accessibility), placement guide, calibration flow (PS-04).
- [ ] **P3-08 Free training** — PS-80 (local only for now).
**Exit:** accuracy ≥ 98 % on the eval set; 0 reps on cheat vectors; performance budget (doc 05 §7) met on target devices.

## Phase 4 — Wake Challenge end-to-end
- [ ] **P4-01 [BE] Sessions & stats schema** — new migrations for `wake_attempts`, `streaks` and the sessions/stats tables of doc 11 §4–5 (`alarm_schedules` already exists from P2-09) + RLS + pgTAP.
- [ ] **P4-02 Integrity** — device key registration (`register-device`), App Attest / Play Integrity, rep-log signing (doc 06 §3).
- [ ] **P4-03 [BE] submit-rep-session** — full validation (doc 06 §4), `app.apply_validated_session` transaction, wake decision rules (doc 04 §3, §7), streaks (personal + pure), Wake Score (doc 08 §3), idempotency, tests with fixtures.
- [ ] **P4-04 Wake flow** — ring → camera → mode rules (all 5 modes) → completion/failure screens (PS-30…PS-34), nag chain & in-app alarm sound (iOS), service-driven sound (Android), give-up flow.
- [ ] **P4-05 SyncEngine** — outbox upload, retries, "pending" UI → validated values (PS-90).
- [ ] **P4-06 Wake tab** — PS-10…PS-15 with real data.
- [ ] **P4-07 Anti-cheat client checks** — phone motion, single person, continuity, replay heuristics (doc 06 §2, items 1–4).
**Exit:** a full week of real wake-ups on both platforms with correct streaks/points on the server; cheat attempts rejected.

## Phase 5 — Stats, progress, achievements
- [ ] **P5-01 [BE] Personal aggregates & PRs** — `user_stats_local_daily`, `personal_records`, `get_stats` RPC.
- [ ] **P5-02 Chart components** — doc 10 §2 charts 1–7 with the design spec, scrubbing, animation, accessibility (audio graph / summaries).
- [ ] **P5-03 Stats dashboard** — KPI tiles, period picker, all charts.
- [ ] **P5-04 [BE] Achievements & XP** — definitions seed (≥ 40), evaluator, XP/levels.
- [ ] **P5-05 Achievements UI + PR celebrations + share cards** (doc 10 §3–6).

## Phase 6 — Social, leaderboards, notifications, widgets
- [ ] **P6-01 [BE] Friendships** — schema, RPCs, blocks, pgTAP.
- [ ] **P6-02 Friends UI** — search, requests, QR/link, friend profile, activity feed, kudos.
- [ ] **P6-03 [BE] Leaderboards** — aggregates, snapshot cron, `get_leaderboard`, `my_rank`, shadow mode for low trust.
- [ ] **P6-04 Ranks tab** — PS-60…PS-63 (wake, streak, total; battles/clans tabs show "coming soon" until phases 7/8).
- [ ] **P6-05 [BE] Push pipeline** — `push_outbox`, `push-send` (APNs + FCM), device tokens, prefs, quiet hours, caps.
- [ ] **P6-06 Notifications client** — registration, categories settings, deep link handling, silent refresh push for iOS alarm window.
- [ ] **P6-07 Widgets** — next alarm + streak (iOS WidgetKit, Android Glance).

## Phase 7 — Battles
- [ ] **P7-01 [BE] Battles & ranking schema** — `0006` + RLS + pgTAP; seasons seed.
- [ ] **P7-02 Trophy & MMR math** — shared test vectors (`trophies/`), implemented in SQL (authoritative) + client display helpers; Glicko-2 in SQL/TS with tests.
- [ ] **P7-03 Ghost battles** — offline-ish first battle mode to build the battle UI without networking.
- [ ] **P7-04 SPIKE LiveKit camera sharing** — one capture feeding MediaPipe + LiveKit on both platforms; CPU/thermal budget.
- [ ] **P7-05 Battle infrastructure** — `battle-token`, `battle-clock`, `battle-ready`, Realtime channels, `battle_push_rep`, `settle-battle`, timeouts.
- [ ] **P7-06 Friend battles (all 5 modes)** — invites, lobby, ready check, countdown, live HUDs, results, rematch, disconnect handling.
- [ ] **P7-07 Quick match** — queue, matchmaking job, ranked trophies, placement, streak bonus, floors.
- [ ] **P7-08 Liveness prompts & battle reports** — doc 06 §2 item 5, §6.
- [ ] **P7-09 Seasons** — rollover job, rewards, history; Battles leaderboard tab enabled.
- [ ] **P7-10 Moderation tooling v1** — flags list, review clips, actions, trophy reversal (doc 06 §6, doc 08 §2.4).

## Phase 8 — Clans & Clan Wars
- [ ] **P8-01 [BE] Clans schema & RPCs** — `0007`, roles/permissions, join flows, pgTAP.
- [ ] **P8-02 Clan UI** — discovery, create, clan home, members, roles management.
- [ ] **P8-03 [BE] Clan wars** — roster lock, matchmaking, scoring with caps (test vectors `clan-war/`), finalize, rewards, Realtime ticker.
- [ ] **P8-04 War UI** — war card, live ticker, history, chests.
- [ ] **P8-05 Clan chat** — messages, kudos, system messages, moderation, rate limits.
- [ ] **P8-06 Clans leaderboard tab** enabled.

## Phase 9 — Ads, compliance, beta & launch
- [ ] **P9-01 Consent** — UMP, ATT pre-prompt, analytics consent (PostHog), Sentry.
- [ ] **P9-02 AdsGate + placements** — doc 13 §1 with unit tests for every forbidden context.
- [ ] **P9-03 Account deletion & data export** — doc 16 §4.
- [ ] **P9-04 Legal pages & in-app links**.
- [ ] **P9-05 Store assets & review notes** — screenshots, descriptions, demo account, review video, Play declarations (doc 16 §6).
- [ ] **P9-06 Closed beta** — TestFlight + Play closed testing (≥ 50 testers), feedback loop, crash-free ≥ 99.5 %.
- [ ] **P9-07 Release checklist** — doc 18 §6 all green → submit.

## Phase 10 — Pushly Pro
- [ ] **P10-01 RevenueCat setup** — products, entitlement `pro`, SDK integration, `revenuecat-webhook`.
- [ ] **P10-02 Paywall & Pro management** — doc 13 §2, restore purchases.
- [ ] **P10-03 Pro perks** — sounds pack, freezes refill, advanced stats, cosmetics, themes, no ads.
