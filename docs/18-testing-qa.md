# 18 — Testing & QA

## 1. Test pyramid
| Layer | iOS | Android | Backend |
|---|---|---|---|
| Unit (pure logic: RepEngine, occurrences, trophies, health check, AdsGate rules, view models) | Swift Testing (`@Test`) | JUnit5 + Turbine + kotlinx-coroutines-test | `deno test`, pgTAP |
| Shared test vectors | run all `shared/test-vectors/**` | same | trophies / clan-war vectors in pgTAP |
| Snapshot (components, key screens light/dark/large text) | swift-snapshot-testing | Paparazzi | — |
| Integration | Supabase local stack in CI; contract tests of Edge Functions against generated schemas | same | `supabase db reset` + function tests |
| UI / E2E | XCUITest smoke flows | Compose UI tests / Maestro | — |
| Manual device QA | alarm & camera matrix (§3) | same | — |

Coverage goals: RepEngine, alarm domain, trophy/clan math ≥ 95 % lines; view models ≥ 70 %.

## 2. Cross-platform parity checks (CI job `parity.yml`)
1. Run both RepEngines over every push-up vector → write `out/ios.json` and `out/android.json` (counted, rejected by reason, per-rep timestamps). Fail if they differ from `expected` **or from each other** (per-rep tEnd tolerance 1 frame).
2. Same for alarm occurrence vectors (exact match).
3. Trophy/clan war vectors executed in SQL **and** in client display helpers (exact match).

## 3. Device matrix (manual QA, minimum)
| iOS (26+) | Android |
|---|---|
| iPhone 12 (low end CPU baseline) | Pixel 6a (Android 15/16) |
| iPhone 13 mini (small screen) | Samsung Galaxy A35 (One UI, mid range) |
| iPhone 15 | Samsung Galaxy S24 |
| iPhone 17 Pro | Xiaomi Redmi Note 13 (HyperOS — aggressive battery) |
| | OnePlus / Oppo device (aggressive battery) |
| | Android 10 device (minSdk) |

## 4. Alarm QA protocol (every release touching alarms)
Run AT-ALM-01…10 (doc 04 §10). Additionally:
- Silent switch on, Focus "Sleep" on, DND on, low-power mode on, battery saver on.
- Phone locked overnight on charger and off charger.
- Time zone change & DST simulation.
- App updated from previous version with existing alarms (alarms must survive updates).
- 30-night soak test on 4 devices (2 per platform) before each public release: **0 missed rings** is a release gate.

## 5. Push-up QA protocol
- Eval set (held-out vectors, not used for threshold tuning) ≥ 50 vectors from people not in the tuning set → accuracy ≥ 98 %, 0 counted reps on cheat vectors.
- Live test sessions per release: 3 testers × 3 placements × 2 lighting conditions, compare to human count.
- Performance: camera open time, fps, battery drain per doc 05 §7.

## 6. Release checklist
- [ ] CI green (all workflows incl. parity).
- [ ] Alarm 30-night soak passed (0 missed).
- [ ] Push-up eval passed.
- [ ] No ads in forbidden contexts (automated AdsGate tests + manual pass).
- [ ] Crash-free sessions ≥ 99.5 % in beta.
- [ ] RLS pgTAP suite passed against staging.
- [ ] Privacy texts (permission strings, privacy policy) match actual behaviour.
- [ ] Store declarations up to date (doc 16 §6).
- [ ] Migration applied to staging and rolled forward cleanly; backups verified.
- [ ] Release notes written.
