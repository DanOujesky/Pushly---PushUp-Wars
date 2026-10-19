# Development setup

## What runs where
| Part | Windows PC | Mac | GitHub Actions (cloud) |
|---|---|---|---|
| Android app | ✅ Android Studio | ✅ | ✅ `android.yml` (tests + debug APK artifact) |
| iOS app | ❌ (Xcode is macOS-only) | ✅ Xcode 26 | ✅ `ios.yml` (build + tests on a cloud Mac) |
| Supabase backend | ✅ Supabase CLI + Docker Desktop | ✅ | ✅ `supabase.yml` |
| Codegen, reference rules, test vectors | ✅ Python 3 | ✅ | ✅ `contracts.yml` |

Without a Mac: develop Android locally, let `ios.yml` build/test iOS on every push, and ship iOS test builds to
TestFlight from CI (to be added: signing via App Store Connect API key — roadmap Phase 9, or earlier when needed).

## One-time setup
1. **Git + GitHub:** create a private GitHub repo and push this folder (`git remote add origin …; git push -u origin main`).
   CI workflows run automatically on push.
2. **Python 3.12+** with `pip install pyyaml` — for `tools/codegen` and `tools/reference`.
3. **Android:** install Android Studio (latest stable), open the `android/` folder, let Gradle sync.
   Android Studio may offer newer versions of AGP/Kotlin/Compose — accepting is fine; note it in `docs/19-decisions-log.md`.
4. **Supabase:** install Docker Desktop and the Supabase CLI (`npm i -g supabase` or `scoop install supabase`), then:
   ```bash
   supabase start          # local stack (API on :54321, Studio on :54323)
   supabase db reset       # apply migrations + seed
   supabase test db        # pgTAP tests
   ```
   No Docker? `tools/db-sandbox/run-tests.sh` runs the same migrations + tests against a plain Postgres 15/16.
5. **Deno 2** (for Edge Function tests): `cd supabase/functions && deno test --allow-env`.
6. **iOS (on a Mac):** `brew install xcodegen`, then `cd ios && xcodegen generate && open Pushly.xcodeproj`.
   Copy `ios/Config/Secrets.example.xcconfig` → `Secrets.xcconfig` and fill in your Team ID.

## Everyday commands
```bash
tools/codegen/run.sh            # after editing shared/design-tokens or shared/rep-engine-spec
tools/reference/run.sh          # reference-rule tests + check that test vectors are current
tools/reference/run.sh --write  # regenerate test vectors after an approved rule change
tools/db-sandbox/run-tests.sh   # DB tests without Docker (needs a running Postgres, run as a superuser)
cd android && ./gradlew test assembleDebug
```

## Working with Claude Code
Open this folder in Claude Code and work task by task from `docs/17-roadmap.md` (see `README.md` for the prompts).
Check `docs/STATUS.md` first — it says what is done, what is verified and what is not.
