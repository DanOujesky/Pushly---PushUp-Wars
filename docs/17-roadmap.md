# 17 — Roadmap (build order)

Rules:
- Work **phase by phase, task by task**. Don't start a task whose dependencies aren't done.
- Every task follows CLAUDE.md §7 (workflow) and §8 (definition of done) and ships on **both** platforms unless marked `[iOS]`, `[Android]` or `[BE]` (backend only).
- **Spikes** are time-boxed experiments; their output is a short report appended to `docs/19-decisions-log.md` and possibly doc updates. Spikes can produce throwaway code in `spikes/` (never merged into app modules).
- Tick tasks `[x]` here when done; `[~]` = written but not yet verified by a real build. `docs/STATUS.md` has the details.

---

## Phase 0 — Foundations
- [x] **P0-01 Monorepo scaffold** — folders per CLAUDE.md §3, `.gitignore`, `README.md` (dev setup), `.editorconfig`, licence placeholder.
- [x] **P0-02 iOS project** — Xcode project `Pushly`, bundle id `app.pushly`, iOS 26 deployment target, Swift 6 strict concurrency, schemes Debug/Staging/Release with `.xcconfig`, local SPM packages for every module in doc 03 §3 (empty), SwiftLint + swift-format, App Group `group.app.pushly`, Widget Extension target (empty).
- [~] **P0-03 Android project** — Gradle Kotlin DSL, version catalog, modules per doc 03 §3, `applicationId app.pushly`, minSdk 29, Compose + Material 3, Hilt, ktlint + detekt, build types debug/staging/release.
- [x] **P0-04 Supabase local** — `supabase init`, config, migration `0001_extensions_enums`, seed, pgTAP set-up, `deno` tooling for functions with a hello function + test.
- [x] **P0-05 Codegen** — `tools/codegen/run.sh`: design tokens → Swift/Kotlin; JSON Schemas → Swift `Codable` / Kotlin `@Serializable`; rep-engine YAML → constants. CI check that generated files are up to date.
- [x] **P0-06 CI** — GitHub Actions: `ios.yml` (build+test on macOS runner), `android.yml`, `supabase.yml` (db reset + pgTAP + deno test), `contracts.yml` (schema lint + codegen diff). Required on PRs.
- [x] **P0-07 Core module** — `PLog`, `Clock` abstraction (injectable), `AppError`, feature-flag reader, build config access — both platforms.
- [x] **P0-08 App shell** — 5-tab navigation (doc 02 §1) with placeholder screens, router, deep-link parser (doc 15 §3) with unit tests.
**Exit:** both apps launch to the tab bar; CI green on all 4 workflows.

## Phase 1 — Design system, auth, profile
- [x] **P1-01 Design tokens** — `tokens.json` with all values from doc 14; generated themes; light/dark; contrast check script.
- [~] **P1-02 Components** — all components in doc 14 §4 except charts, with SwiftUI previews / Compose previews and snapshot tests.
- [x] **P1-03 [BE] Profiles & devices** — migrations `0002`, RLS, `update_profile`, signup trigger creating `profiles`, pgTAP tests.
- [~] **P1-04 Auth** — Sign in with Apple (iOS), Google (both), email OTP (both) via Supabase Auth; session persistence; sign-out; guest mode flag.
- [x] **P1-05 Onboarding UI** — PS-01 to PS-03 (value screens, sign-in, profile setup with username availability check, avatar presets, country, age gate 16+).
- [x] **P1-06 Profile screen shell & settings** — PS-73 structure (privacy toggles functional; other items stubbed).
- [x] **P1-07 Remote config** — `app_config` table + client reader + force-update screen.
**Exit:** a new user can sign up on either platform, set a profile, see it after reinstall.

## Phase 2 — Alarm system (no camera yet)
- [~] **P2-01 SPIKE [iOS] AlarmKit** (code assumes doc 04 §5 with a 64-alarm safety cap; device checklist in `docs/qa/phase-2-alarm-device-tests.md` — needs a signed build on an iPhone) — verify: per-app alarm limit, fixed-date one-shot alarms, custom sound length/format limit, stop/secondary intents behaviour (incl. the bottom-edge dismissal quirk), reboot, app update, offload, Live Activity countdown. Report → decisions log; adjust doc 04 §5.
- [~] **P2-02 SPIKE [Android] ringing** (real devices: checklist in `docs/qa/phase-2-alarm-device-tests.md`; CI emulator job ready but not booting on hosted runners) — `setAlarmClock`, FGS type (`systemExempted` vs `mediaPlayback`) on Android 14/15/16, full-screen intent on locked screen, direct boot re-arm, OEM tests (Samsung, Xiaomi, Pixel). Report → decisions log.
- [x] **P2-03 Alarm domain** — `AlarmSchedule` model + validation (doc 04 §2), pure `occurrences()` and `challengeOccurrence()` + **alarm-occurrence test vectors** (≥ 25 incl. DST cases) passing on both.
- [x] **P2-04 Local persistence** (one JSON document, D-035) — SwiftData/Room models for alarms, outbox.
- [x] **P2-05 AlarmScheduler** — iOS (rolling window, nag chain API, reconcile) and Android (next-occurrence, receivers, integrity worker) per doc 04 §5–6; idempotent `sync` with unit tests.
- [~] **P2-06 Alarm editor UI** (done except the overrides calendar and sound import — Q-08) — PS-20…PS-26: list, create/edit, per-weekday times grid, overrides calendar, skip next, pause, modes picker with validation, sounds (bundled + import), test alarm.
- [x] **P2-07 Ring experience** (verified on emulator / simulator; real-device runs pending) — iOS AlarmKit presentation + intents + Live Activity; Android `AlarmRingService` + `RingActivity`. "Start push-ups" opens a placeholder wake screen (debug-only "Complete" button compiled out of release).
- [x] **P2-08 Alarm health check** — doc 04 §8 pure function + banners + evening local notification.
- [x] **P2-09 [BE] Alarm sync** (RPC `sync_alarms`, D-036) — `alarm_schedules` + versions migration, RLS, `sync-alarms` function, client sync via outbox.
- [x] **P2-10 Permissions explainers** — pre-permission screens for AlarmKit / exact alarm / FSI / notifications / battery.
**Exit:** acceptance tests AT-ALM-01…09 pass (doc 04 §10) on QA devices; AT-ALM-10 (30 nights) starts running in the background of later phases.

## Phase 3 — Camera, pose & rep engine
- [ ] **P3-01 SPIKE pose performance** — MediaPipe full vs lite fps & latency on the device matrix (doc 18 §3); camera sharing approach for later LiveKit use. Report. *(Debug builds show fps + model on screen; needs real phones.)*
- [x] **P3-02 CameraSource** — doc 05 §2 both platforms, orientation, latest-frame strategy, low-light detection.
- [x] **P3-03 PoseEngine** — MediaPipe wrapper → `PoseFrame`, model selection, pre-warm, thermal handling.
- [x] **P3-04 Pose recorder tool** — debug-only screen recording `PoseFrame` JSON for test vectors (doc 05 §8).
- [ ] **P3-05 Test vector collection** — ≥ 200 labelled vectors incl. all cheat types (human task with tool support; Claude prepares checklists & scripts). *(Tooling + checklist ready: `docs/qa/pose-recording.md`; 25 synthetic vectors in place.)*
- [x] **P3-06 RepEngine** — smoother, features, placement detector, state machine, evaluation, hints — **pure**, constants from YAML; passes **all** vectors on both platforms; cross-platform parity test in CI (both engines' outputs compared).
- [~] **P3-07 Camera session UI** — counter, body frame overlay, hints, haptics/sounds, speech counting (accessibility), placement guide, calibration flow (PS-04). *(Done except the placement guide screen + calibration flow.)*
- [x] **P3-08 Free training** — PS-80 (local only for now).
**Exit:** accuracy ≥ 98 % on the eval set; 0 reps on cheat vectors; performance budget (doc 05 §7) met on target devices.

## Phase 4 — Wake Challenge end-to-end
- [x] **P4-01 [BE] Sessions & stats schema** — new migrations for `wake_attempts`, `streaks` and the sessions/stats tables of doc 11 §4–5 (`alarm_schedules` already exists from P2-09) + RLS + pgTAP.
- [~] **P4-02 Integrity** — device key registration (`register-device`), App Attest / Play Integrity, rep-log signing (doc 06 §3). *(Device keys + signed logs done (D-047); App Attest / Play Integrity attestation pending.)*
- [~] **P4-03 [BE] submit-rep-session** — full validation (doc 06 §4), `app.apply_validated_session` transaction, wake decision rules (doc 04 §3, §7), streaks (personal + pure), Wake Score (doc 08 §3), idempotency, tests with fixtures. *(Signatures (D-047) and the feature-trace check (D-046) done; attestation → P4-02 part 2.)*
- [x] **P4-04 Wake flow** — ring → camera → mode rules (all 5 modes) → completion/failure screens (PS-30…PS-34), nag chain & in-app alarm sound (iOS), service-driven sound (Android), give-up flow.
- [x] **P4-05 SyncEngine** — outbox upload, retries, "pending" UI → validated values (PS-90).
- [~] **P4-06 Wake tab** — PS-10…PS-15 with real data. *(Streak, week strip, push-ups today, pending marker done; clan contribution + global rank come with Phases 6/8.)*
- [~] **P4-07 Anti-cheat client checks** — phone motion, single person, continuity, replay heuristics (doc 06 §2, items 1–4). *(Motion, second person, continuity, limb-length replay signal + server-checked feature trace done (D-046); flicker/border heuristics need device data.)*
**Exit:** a full week of real wake-ups on both platforms with correct streaks/points on the server; cheat attempts rejected.

## Phase 5 — Stats, progress, achievements
- [x] **P5-01 [BE] Personal aggregates & PRs** — `user_stats_local_daily`, `personal_records`, `get_stats` RPC. *(migration 0010, contract `stats.schema.json`)*
- [~] **P5-02 Chart components** — doc 10 §2 charts 1–7 with the design spec, scrubbing, animation, accessibility (audio graph / summaries). *(1–4 + 6 done, D-049; 5 needs per-day form metrics, 7 = Phase 7)*
- [~] **P5-03 Stats dashboard** — KPI tiles, period picker, all charts.
- [x] **P5-04 [BE] Achievements & XP** — definitions seed (≥ 40), evaluator, XP/levels. *(D-048; 44 definitions, `get_achievements`)*
- [~] **P5-05 Achievements UI + PR celebrations + share cards** (doc 10 §3–6). *(achievements screen + rewards on result screens done; share cards, confetti open)*

## Phase 6 — Social, leaderboards, notifications, widgets
- [x] **P6-01 [BE] Friendships** — schema, RPCs, blocks, pgTAP. *(migration 0011, D-050; feed + kudos too)*
- [~] **P6-02 Friends UI** — search, requests, QR/link, friend profile, activity feed, kudos. *(search, requests, share link, feed + kudos, block; QR code + friend profile open)*
- [x] **P6-03 [BE] Leaderboards** — aggregates, snapshot cron, `get_leaderboard`, `my_rank`, shadow mode for low trust. *(0011 + 0013; my rank is part of `get_leaderboard`)*
- [~] **P6-04 Ranks tab** — PS-60…PS-63 (wake, streak, total; battles/clans tabs show "coming soon" until phases 7/8). *(built; CI green 2026-10-21)*
- [~] **P6-05 [BE] Push pipeline** — `push_outbox`, `push-send` (APNs + FCM), device tokens, prefs, quiet hours, caps. *(built + tested; needs APNs key + Firebase service account, docs/RELEASING.md)*
- [~] **P6-06 Notifications client** — registration, categories settings, deep link handling, silent refresh push for iOS alarm window. *(registration + in-context prompts + categories + deep links done, D-058; silent refresh push open; needs APNs/Firebase secrets)*
- [x] **P6-07 Widgets** — next alarm + streak (iOS WidgetKit, Android Glance). *(D-059; home + iOS lock screen)*

## Phase 7 — Battles
- [x] **P7-01 [BE] Battles & ranking schema** — `0006` + RLS + pgTAP; seasons seed. *(migration 0014, D-051)*
- [~] **P7-02 Trophy & MMR math** — shared test vectors (`trophies/`), implemented in SQL (authoritative) + client display helpers; Glicko-2 in SQL/TS with tests. *(SQL + vectors done; client BattleRules on both platforms, D-055)*
- [x] **P7-03 Ghost battles** — offline-ish first battle mode to build the battle UI without networking. *(migrations 0018–0019, both apps, opt-out)*
- [ ] **P7-04 SPIKE LiveKit camera sharing** — one capture feeding MediaPipe + LiveKit on both platforms; CPU/thermal budget.
- [~] **P7-05 Battle infrastructure** — `battle-token`, `battle-clock`, `battle-ready`, Realtime channels, `battle_push_rep`, `settle-battle`, timeouts. *(backend: battle-token, rep push, ready/finish/forfeit, settlement + cron; Realtime broadcast + clock in client work)*
- [~] **P7-06 Friend battles (all 5 modes)** — invites, lobby, ready check, countdown, live HUDs, results, rematch, disconnect handling. *(all 5 modes without video: Best of 3 + Turns HUDs 2026-10-21, migration 0020; rematch for friend battles; video open)*
- [~] **P7-07 Quick match** — queue, matchmaking job, ranked trophies, placement, streak bonus, floors. *(backend done)*
- [ ] **P7-08 Liveness prompts & battle reports** — doc 06 §2 item 5, §6.
- [~] **P7-09 Seasons** — rollover job, rewards, history; Battles leaderboard tab enabled. *(rollover + battles board + season results/badges, migration 0022; cosmetic frames with the shop)*
- [ ] **P7-10 Moderation tooling v1** — flags list, review clips, actions, trophy reversal (doc 06 §6, doc 08 §2.4).

## Phase 8 — Clans & Clan Wars
- [x] **P8-01 [BE] Clans schema & RPCs** — `0007`, roles/permissions, join flows, pgTAP. *(migration 0015, D-052)*
- [~] **P8-02 Clan UI** — discovery, create, clan home, members, roles management. *(built; CI green 2026-10-21)*
- [~] **P8-03 [BE] Clan wars** — roster lock, matchmaking, scoring with caps (test vectors `clan-war/`), finalize, rewards, Realtime ticker. *(all but Realtime broadcast; chests granted on finalize, migration 0021, D-057)*
- [~] **P8-04 War UI** — war card, live ticker, history, chests. *(war card, history + streak, chests with medals; live ticker = polling until Realtime)*
- [~] **P8-05 Clan chat** — messages, kudos, system messages, moderation, rate limits. *(backend + chat screens with 5 s refresh; Realtime later)*
- [~] **P8-06 Clans leaderboard tab** enabled. *(backend `get_clan_leaderboard`)*

## Phase 9 — Ads, compliance, beta & launch
- [ ] **P9-01 Consent** — UMP, ATT pre-prompt, analytics consent (PostHog), Sentry.
- [~] **P9-02 AdsGate + placements** — doc 13 §1 with unit tests for every forbidden context. *(AdsGate + vectors done, D-054; AdMob SDK + placements need ad unit IDs)*
- [x] **P9-03 Account deletion & data export** — doc 16 §4. *(backend D-053; Account & data screens on both platforms, ghost opt-out 0019)*
- [x] **P9-04 Legal pages & in-app links**. *(final texts EN/CS, GitHub Pages site, welcome acceptance + Profile links — D-056; paywall links come with Pro)*
- [~] **P9-05 Store assets & review notes** — screenshots, descriptions, demo account, review video, Play declarations (doc 16 §6). *(texts in docs/store/listing.md, form answers in docs/store/compliance.md; screenshots open)*
- [ ] **P9-06 Closed beta** — TestFlight + Play closed testing (≥ 50 testers), feedback loop, crash-free ≥ 99.5 %.
- [ ] **P9-07 Release checklist** — doc 18 §6 all green → submit.

## Phase 10 — Pushly Pro
- [~] **P10-01 RevenueCat setup** — products, entitlement `pro`, SDK integration, `revenuecat-webhook`. *(webhook + entitlements done; SDK + products need the RevenueCat account)*
- [ ] **P10-02 Paywall & Pro management** — doc 13 §2, restore purchases.
- [ ] **P10-03 Pro perks** — sounds pack, freezes refill, advanced stats, cosmetics, themes, no ads.
