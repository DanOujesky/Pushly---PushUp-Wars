# Project status

_Last updated: 2026-10-19 — Phase 0 (foundations) in progress._

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

## Written but NOT yet verified (no Swift/Kotlin toolchain in the authoring environment)
| Area | What | First verification step |
|---|---|---|
| iOS | XcodeGen `project.yml`, configs, `Core` / `DesignSystem` / `RepEngine` packages, 5-tab shell, `AppRouter` + deep links, widget extension stub, tests | push to GitHub → `ios.yml`, or on a Mac: `xcodegen generate` + run tests |
| Android | Gradle catalog + wrapper 8.14.3, `:app`, `:core:common`, `:core:designsystem`, `:engine:rep`, 5-tab shell, deep links, tests | open `android/` in Android Studio → Sync → `./gradlew test assembleDebug` |
| CI | `supabase.yml`, `contracts.yml`, `android.yml`, `ios.yml` | first push to GitHub |

Expect a few small compile fixes on the first build (exact library versions, SDK API names). Fix them before starting Phase 1.

## Roadmap progress (Phase 0)
- [x] P0-01 Monorepo scaffold
- [~] P0-02 iOS project — written, unverified
- [~] P0-03 Android project — written, unverified; ktlint/detekt/Hilt not added yet (add after the first successful sync)
- [x] P0-04 Supabase local (config, migrations, seed, tests, function tooling)
- [x] P0-05 Codegen — tokens + rep-engine spec done; JSON-Schema → models comes with the first contract (P2-09)
- [~] P0-06 CI — workflows written, never run
- [~] P0-07 Core module — written on both platforms, unverified
- [~] P0-08 App shell + deep-link parser — written on both platforms, unverified
- Ahead of schedule (backend only, verified): P1-03 profiles & devices, P1-07 `app_config` table; P1-01 design tokens (data part)
- Ahead of schedule (shared, verified): reference rules + test vectors for P2-03, P7-02, P8-03

## Needs Dan
- First Android Studio sync + build; first push to GitHub so `ios.yml` builds iOS on a cloud Mac.
- Decisions in `docs/19-decisions-log.md` → Open questions (domain, sounds, brand, pricing).
- Apple Team ID in `ios/Config/Secrets.xcconfig` (local) / CI secrets.
