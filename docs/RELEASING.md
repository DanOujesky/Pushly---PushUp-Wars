# Releasing test builds (TestFlight + Google Play)

App ID on both stores: **`app.pushly`** (App Store Connect app + Play Console app created 2026-10-20).
Everything builds in GitHub Actions — no Mac and no Android Studio needed. Secrets live only in
GitHub → Settings → Secrets and variables → Actions (never in the repo or in chat).

## iOS → TestFlight (workflow `ios-testflight`)
One-time setup:
1. **Team ID** — developer.apple.com → Account → Membership details → *Team ID* (10 characters).
   Secret **`APPLE_TEAM_ID`**.
2. **API key** — App Store Connect → Users and Access → Integrations → App Store Connect API → *Team Keys* → **+**,
   name "GitHub CI", access **Admin** (needed so CI may create the signing certificate and profiles itself).
   - Secret **`ASC_KEY_ID`** = Key ID of the new key.
   - Secret **`ASC_ISSUER_ID`** = Issuer ID shown above the key list.
   - Download the `.p8` file (only possible once), open it in Notepad and paste the **whole** content incl. the
     `-----BEGIN PRIVATE KEY-----` lines into secret **`ASC_KEY_P8`**. Keep the file somewhere private.

Signing happens inside the run (`tools/ci/asc_sign.py`): it registers the bundle IDs + capabilities, creates a
temporary Apple Distribution certificate and App Store profiles, signs, uploads, and deletes them again. Check without
building: Actions → **ios-signing-check**.

One-time portal step for the App Group (the API can't do it; until then builds go out without it and the app keeps
its alarms in its own container — they are moved over automatically later): developer.apple.com → Certificates,
Identifiers & Profiles → Identifiers → **+** → *App Groups* → `group.app.pushly`. Then open the identifiers
`app.pushly` and `app.pushly.widgets` → *App Groups* → *Configure* → tick `group.app.pushly` → Save.

Each build: GitHub → Actions → **ios-testflight** → *Run workflow* → flavor:
- `internal` (default) — Debug build with tester tools (Pose recorder, debug "Complete" button). Internal testers only.
- `release` — exactly what the App Store gets.

After ~10–30 min the build shows in App Store Connect → TestFlight. First time: TestFlight → *Internal Testing* → **+**
group → add yourself (your Apple ID must be a user of the App Store Connect team) → install the **TestFlight** app on
the iPhone and accept. The iPhone needs **iOS 26** (AlarmKit).

## Android → Google Play (workflows `android-keystore`, `android-release`)
One-time setup:
1. Actions → **android-keystore** → *Run workflow*. When done, open the run → artifact **pushly-upload-key** (zip):
   - content of `ANDROID_KEYSTORE_B64.txt` → secret **`ANDROID_KEYSTORE_B64`**
   - content of `ANDROID_KEYSTORE_PASSWORD.txt` → secret **`ANDROID_KEYSTORE_PASSWORD`**
   - keep the zip somewhere private (backup), then delete the artifact on the run page.
2. Actions → **android-release** → *Run workflow* → artifact **pushly-release-aab** → unzip → `app-release.aab`.
3. Play Console → Pushly → *Test and release* → **Internal testing** → *Create new release* → accept **Play App
   Signing** (Google keeps the app signing key; ours is only the upload key) → upload the `.aab` → *Save* → *Review*
   → *Roll out*. Play shows a checklist of declarations (privacy policy URL, app access, ads, content rating, target
   audience, data safety) — internal testing may need some of them filled in first.
4. *Testers* tab → create an email list with your Google account → open the opt-in link on the phone → install from Play.

Every next build: run **android-release**, upload the new `.aab` the same way (the build number = workflow run
number, so it always increases). Automatic upload to Play (service account) can be added later.

Note: the Play build is a release build — no debug tools. For the Pose recorder on Android keep using the
`pushly-debug-apk` from the `android` workflow (it installs next to the Play app as "app.pushly.debug").
