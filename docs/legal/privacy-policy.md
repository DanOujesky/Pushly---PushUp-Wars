# Pushly — Privacy Policy (DRAFT)

> Draft prepared from how the app actually works (docs 06, 11, 16). Not legal advice: have it reviewed before
> launch, fill in every `[…]`, and keep it in sync with the processors list. Effective date: `[date]`.

**Controller:** `[full name / company]`, `[address]`, Czech Republic. Contact: `[privacy@pushly.app]`.

## 1. What Pushly is
Pushly is a push-up alarm and fitness game. Your alarm only stops after real push-ups, counted by your phone's
camera. You can also battle other people, join clans and appear on leaderboards.

## 2. The camera — what we do and don't do
- The camera picture is analysed **on your phone** to find body points (shoulders, elbows, hips…) and count reps.
- **We never upload, store or record your camera video.** Live battle video goes directly to your opponent through
  our video provider (LiveKit) and is not recorded.
- What we do send after a session: the reps (timestamps, a 0–100 form score per rep) and a compact numeric trace of
  the body angles at 10 times per second, used to detect cheating. This trace contains numbers only — no images,
  no face data, no biometric template. Raw session logs are deleted after 90 days.

## 3. Data we process
| Data | Why | Legal basis (GDPR art. 6) | Kept |
|---|---|---|---|
| Email address (or Apple / Google sign-in id) | your account, sign-in | contract | until you delete the account |
| Username, avatar, country, time zone, birth year | profile, local days, age check (16+) | contract | until deletion |
| Alarms and their settings | sync between your devices; the wake challenge rules | contract | until deletion |
| Workout data: reps, sessions, wake results, streaks, XP, achievements, trophies | the game, statistics, leaderboards | contract | until deletion |
| Anti-cheat data: numeric body-angle trace, device key, integrity checks, flags | fair competition | legitimate interest (fair play) | traces 90 days; flags until deletion |
| Friends, blocks, kudos, clan membership, clan chat messages | social features | contract | until deletion; chat 90 days |
| Battle results and rep events | battles, rankings | contract | until deletion (opponents keep your username snapshot as "Deleted user" after deletion) |
| Push notification token | notifications you allow | consent (OS permission) | until you sign out / delete |
| Reports you send | safety and moderation | legitimate interest | up to 2 years |
| Purchases (Pushly Pro, later) | unlocking Pro | contract | as long as required by law |
| Crash reports (Sentry), product analytics (PostHog, EU) — when added | fix bugs, improve the app | consent where required | up to 90 days |
| Ads (Google AdMob, later) | free app funded by ads | consent (UMP); otherwise non-personalised | per Google's policy |

We do **not** sell your data. We do not use your data for automated decisions with legal effects; anti-cheat checks
can exclude a session from leaderboards, and you can contact us if you think that was wrong.

## 4. Who else processes data (processors)
Supabase (database, sign-in, functions — EU region), LiveKit (battle video transit, not recorded), Apple (APNs push,
Sign in with Apple, App Attest), Google (FCM push, Play Integrity, AdMob + UMP when ads start), RevenueCat
(subscriptions, when Pro starts), Sentry and PostHog (when added; EU hosting). Transfers outside the EU rely on the
EU–US Data Privacy Framework or standard contractual clauses.

## 5. Who can see what
- Your username, avatar, level, trophies and clan tag are visible to other users.
- Your streak is visible to everyone, friends only or nobody, depending on your profile visibility setting.
- You can hide yourself from leaderboards ("Anonymous athlete").
- Blocking someone hides you from each other everywhere.

## 6. Your rights
In the app (Profile → Account & data) you can **download your data** (JSON) and **delete your account** at any
time. Deleting the account doesn't cancel an App Store / Google Play subscription — cancel it in the store.
You also have the right to access, correct, restrict, object and complain to the Czech data protection authority
(ÚOOÚ, www.uoou.cz). Contact: `[privacy@pushly.app]`.

## 7. Age
You must be at least **16** to create an account. The alarm works without an account.

## 8. Security
Encrypted connections, row-level access rules in the database (you can only read your own private data), signed
workout logs, no camera video on our servers.

## 9. Changes
We'll tell you in the app before important changes take effect.
