# 16 — Privacy, security & compliance

> Not legal advice — the founder must have the final privacy policy and terms reviewed by a lawyer before launch. This doc lists what the app must technically support.

## 1. Data principles
- **Data minimisation:** video never leaves the device (except opt-in review clips, doc 06 §6). We store derived numbers (rep timing, angles, quality) — not images, not face data.
- **EU hosting:** Supabase project in the EU (Frankfurt), PostHog EU cloud, Sentry EU region where available.
- **Processors** (list in the privacy policy): Supabase, LiveKit (battle video transit, not recorded), RevenueCat, Google (AdMob, UMP, FCM, Play Integrity), Apple (APNs, App Attest, Sign in with Apple), Sentry, PostHog.

## 2. Age
- Minimum age **16** (age gate by birth year at sign-up; under 16 → cannot create an account; the alarm-only guest mode is allowed without an account). Rationale: simplest GDPR-safe choice for an app with chat, strangers in live video battles, and ads (decisions log D-015; revisit later).
- Store ratings: **16+** on the App Store (matches the account age) / Play target audience 16–17 + 18+; answers in `docs/store/compliance.md`.

## 3. Consent & permissions
| Item | When requested | Notes |
|---|---|---|
| Camera | before first push-up session (onboarding PS-04) with explainer | `NSCameraUsageDescription`: "Pushly uses the camera to count your push-ups. Video is analysed on your device and never stored." |
| Microphone | only when enabling mic in a friendly battle | `NSMicrophoneUsageDescription` |
| Alarms (AlarmKit) | when enabling the first alarm | `NSAlarmKitUsageDescription` (doc 04) |
| Notifications | in context (doc 02 PS-06) | |
| Exact alarms / full-screen intent / battery (Android) | alarm setup + health check | explainer screens |
| Motion sensors | iOS: no permission needed for CoreMotion device motion; Android: none | used only during sessions (doc 06 §2) |
| Tracking (ATT, iOS) | after 3rd completed session | pre-prompt; denial → non-personalised ads |
| Ads consent (UMP) | first app launch in EEA/UK/CH, before any ad request | re-openable in Settings → Privacy |
| Analytics | covered by consent screen in EEA (PostHog opt-in) | no analytics before consent |
| Review clips | when offered (doc 06 §6) | separate explicit consent, revocable |
| Health/exercise disclaimer | onboarding, must accept | "Exercise at your own risk; consult a doctor if you have health conditions." |

## 4. User rights (in-app)
- **Delete account** in Settings (Apple requires in-app deletion) → `account-delete` (doc 12). Deleting the account does **not** cancel an App Store / Google Play subscription — the deletion screen must say so and link to the store's subscription management.
- **Export data** (JSON) → `data-export`.
- Profile visibility, leaderboard visibility, ghost-run contribution opt-out, analytics opt-out.

## 5. Security
- Supabase RLS everywhere (doc 11 §9); pgTAP tests in CI.
- Edge Functions verify JWT and validate schemas; service role key only server-side.
- Device integrity: App Attest / Play Integrity (doc 06 §3).
- Secrets: CI secrets / Supabase secrets only; no secrets in the apps except public anon key and publishable SDK keys (RevenueCat public key, AdMob app id).
- Certificate pinning: **not** used (operational risk); rely on TLS + integrity tokens.
- Dependency scanning: Dependabot / Renovate for SPM, Gradle, npm/Deno.
- Abuse: rate limits (doc 12 §6), profanity filter for usernames/clan names/chat, report & block everywhere a user can see another user.

## 6. Store review notes (prepare in Phase 9)
**Apple App Store**
- Guideline 5.1.1(v): in-app account deletion ✅.
- Sign in with Apple offered alongside Google ✅ (4.8).
- Camera use clearly explained; on-device processing statement.
- AlarmKit usage justified (core feature).
- Live video with strangers: report/block, ranked battles mic off, safety statement in review notes (1.2 user-generated content: filter, report, block, contact info).
- Provide a demo account + instructions for reviewers (how to test alarm and push-up counting; offer a short video).

**Google Play**
- Declarations: exact alarm (`SCHEDULE_EXACT_ALARM` / possibly `USE_EXACT_ALARM`), full-screen intent (alarm functionality), foreground service type (with a demo video), camera, advertising ID (Data safety), account deletion URL + in-app.
- Data safety form consistent with §1.
- UGC policy: chat moderation + report/block.

## 7. Legal documents
Final texts in `docs/legal/` (effective 21 Oct 2026; operator Daniel Oujeský, contact dany.oujesky@gmail.com): Privacy Policy (EN + CS), Terms of Use (EN + CS, includes Pro subscription terms), Community Guidelines, account deletion and support pages. Published by `.github/workflows/pages.yml` at `https://danoujesky.github.io/Pushly---PushUp-Wars/` (D-056); linked from the welcome screen (acceptance), Profile, and later the paywall. When processing changes, update the policy and `docs/store/compliance.md` in the same PR and bump `LegalLinks.version` on both platforms.
