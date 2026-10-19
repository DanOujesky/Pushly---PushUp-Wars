# Project status

_Last updated: 2026-10-19 — Phase 0 (foundations) done; all four CI workflows green on GitHub._

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

## Needs Dan
- Try the app: Android — download the `pushly-debug-apk` artifact from the latest `android` run and install it; iOS — needs signing/TestFlight setup (later task).
- Decisions in `docs/19-decisions-log.md` → Open questions (domain, sounds, brand, pricing).
- Apple Team ID in `ios/Config/Secrets.xcconfig` (local) / CI secrets.
