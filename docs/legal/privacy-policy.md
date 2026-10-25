---
title: Privacy Policy
updated: 21 October 2026
---

# Pushly — Privacy Policy

**Effective date:** 21 October 2026 · [Česky](privacy-cs.html)

This policy explains what personal data the Pushly app ("Pushly", "we", "us") processes, why, for how long, and what
rights you have. We wrote it to match how the app actually works. If something is unclear, write to us.

## 1. Who is responsible

The controller of your personal data is **Daniel Oujeský**, a private individual based in Prague, Czech Republic,
who develops and operates Pushly.

- Contact for privacy questions and requests: **dany.oujesky@gmail.com**
- We have not appointed a data protection officer (we are not required to). Write to the address above.

## 2. Pushly in one paragraph

Pushly is a push-up alarm and fitness game. Your alarm only stops after real push-ups, counted by your phone's
camera. You can also battle other people, race recorded "ghost" runs, join clans, chat in your clan and appear on
leaderboards. The alarm works without an account; everything social and competitive needs an account.

## 3. The camera — what happens and what never happens

- The camera picture is analysed **only on your phone**. An on-device model finds body points (shoulders, elbows,
  hips, …) and the app counts your reps from them.
- **We never upload, store or record your camera video or photos.** We do not create face data or biometric
  templates, and we do not use the camera to identify you.
- During **live video battles** (when that feature is available), your camera picture and, only if you turn it on
  in a friendly battle, your microphone are sent live to your opponent through our video provider LiveKit. The video
  is **not recorded** by us or by LiveKit.
- After a session the app sends us: the reps (timestamps and a 0–100 form score per rep), how long the session took,
  and a compact **numeric trace** of a few body angles and phone motion values (about 10 values per second). This
  trace contains numbers only — no images. We use it to check that reps are real (anti-cheat).
- **Optional review clips:** if we ever ask you to become a "Verified athlete" (only for top-100 leaderboard players
  or sessions on hold), the app would, **only with your separate explicit consent**, upload 3-second, low-resolution,
  silent clips of two random reps. They are visible only to moderators and deleted after 30 days. You can refuse or
  withdraw this consent at any time; you then stay off the public top-100 lists but can play normally. This feature
  is not active yet.

## 4. What data we process, why, on what legal basis, and for how long

Legal bases under the GDPR (EU Regulation 2016/679), Article 6(1): **(a) consent**, **(b) performance of our contract
with you** (the Terms of Use — providing the app you asked for), **(c) legal obligation**, **(f) legitimate
interests** (named in each row).

| Data | Purpose | Legal basis | How long we keep it |
|---|---|---|---|
| Email address, or your Sign in with Apple / Google account identifier; sign-in timestamps | Creating your account and signing you in | (b) contract | Until you delete your account |
| Username, avatar choice, country, time zone, birth year | Your public profile; calculating your local day (streaks, wake results); checking you are 16 or older | (b) contract | Until you delete your account |
| Alarm schedules and their settings | Syncing alarms between your devices and checking wake challenge rules. (Alarms ring from your phone, also offline and without an account.) | (b) contract | Until you delete your account; older versions are replaced |
| Workout data: rep sessions, reps, form scores, wake attempts, streaks, statistics, personal records, XP, levels, achievements | The game, your statistics and progress | (b) contract | Until you delete your account |
| Competitive data: trophies, league, rating, battle results, battle rep events, leaderboard positions, clan war results | Battles, rankings, leaderboards and clan wars | (b) contract | Until you delete your account; detailed battle rep events 180 days |
| Anti-cheat data: numeric body-angle and motion trace, signed session logs, device key, device integrity checks (Apple App Attest / Google Play Integrity), trust score, flags | Keeping competition fair and detecting manipulated apps or devices | (f) legitimate interest — fair play for all players | Raw session logs and traces **90 days**; flags and trust score until account deletion |
| Device information: platform, phone model, OS version, app version | Making the app work on your device, support, anti-cheat | (b) contract; (f) legitimate interest — security | Until you delete your account or remove the device |
| Push notification token and notification settings | Sending notifications you turned on (battle challenges, friend requests, clan wars, …) | (a) consent — your phone's notification permission; (b) contract | Until you sign out, revoke the permission or delete your account; sent-notification records 30 days |
| Friends, friend requests, blocks, kudos, activity feed | Social features | (b) contract | Until you delete your account; feed items 30 days |
| Clan membership, clan role, clan chat messages | Clans and clan chat | (b) contract | Until you delete your account; chat messages **90 days** |
| Ghost runs: the timing of your reps from finished battles (no video, no name shown) | Letting other players race an anonymous "ghost" of a similar level | (f) legitimate interest — practice opponents for everyone. You can switch this off in Settings | Until you opt out or delete your account |
| Reports you send or that concern you, moderation decisions | Safety, enforcing the Community Guidelines | (f) legitimate interest — a safe community; (c) legal obligation where applicable | Up to **2 years** after the report is closed |
| Pushly Pro purchase status (product, store, renewal and expiry dates, transaction events) | Unlocking Pro features | (b) contract; (c) legal obligation (accounting) | While your subscription is active and up to 400 days after the last event; longer only where the law requires |
| Technical logs at our hosting provider (e.g. IP address, request time, errors) | Running and securing the service | (f) legitimate interest — security and reliability | Short-term, as set by the provider (typically days) |
| Crash reports (Sentry) — when added | Fixing bugs and crashes | (f) legitimate interest — a working app | Up to 90 days |
| Product analytics (PostHog, EU) — when added | Understanding which features are used, to improve them | (a) consent; you can withdraw it in Settings → Privacy | Up to 12 months |
| Advertising (Google AdMob) | Showing ads that keep Pushly free | (a) consent for personalised ads and for using device identifiers; otherwise only non-personalised ads | As described in Google's policies |

**Is giving us data required?** The alarm works without giving us anything. To create an account you must give a
sign-in method, a username and your birth year — without them we can't provide the account features. Everything else
is optional or created by using the app.

**Where the data comes from:** from you and your app. Integrity results come from Apple or Google; purchase status
from Apple or Google through RevenueCat.

## 5. Automated decisions

Our anti-cheat checks run automatically. A session that looks manipulated can be held back from leaderboards, and
repeated cheating can reduce your trust score or lead to trophy corrections. These decisions do not have legal or
similarly significant effects on you, but you can always ask for a **human review**: write to us and we will look at
it and explain the result. We do not use your data to profile you for marketing.

## 6. Who can see your data

**Other users** can see: your username, avatar, level, trophies, league, achievements and clan tag; your streak,
depending on your profile visibility (everyone / friends / nobody); your position and score on leaderboards, unless you
hide your name there ("Anonymous athlete"); your messages in your clan chat; your live camera picture during a video
battle. Blocking someone hides you from each other.

**Service providers (processors)** that process data for us under data processing agreements:

| Provider | What for | Where |
|---|---|---|
| Supabase Inc. | Database, sign-in, server functions, file storage | EU (hosting region of our project) |
| Apple Inc. | Sign in with Apple, push notifications (APNs), App Attest, App Store purchases | USA / worldwide |
| Google LLC / Google Ireland Ltd. | Google Sign-In, push notifications (Firebase Cloud Messaging), Play Integrity, Google Play purchases; AdMob and the consent tool (UMP) | EU / USA |
| LiveKit Inc. | Relaying live battle video and audio (not recorded) | Nearest server region; may include USA |
| RevenueCat Inc. | Managing Pushly Pro subscriptions | USA |
| Functional Software Inc. (Sentry) | Crash reports — when added | EU region where available |
| PostHog Inc. | Product analytics — when added, only with consent | EU (Frankfurt) |

Apple and Google also process data as independent controllers when you use their app stores and accounts; their own
privacy policies apply to that.

We do **not sell** your personal data and do not share it with data brokers. We may disclose data if the law requires
it (for example a court order) or to protect the safety of users.

## 7. Transfers outside the EU

Some providers are based in the USA. Transfers rely on the **EU–US Data Privacy Framework** where the provider is
certified, or on the European Commission's **Standard Contractual Clauses**. You can ask us for more information.

## 8. Your rights

You have the right to:

- **access** your data and get a copy — in the app: *Profile → Account & data → Download my data* (JSON);
- **rectification** — edit your profile in the app or write to us;
- **erasure** — in the app: *Profile → Account & data → Delete account* (immediate and permanent), or write to us;
- **restriction** of processing;
- **data portability** — the download is in a machine-readable format;
- **object** at any time to processing based on legitimate interests (Article 21), including ghost runs (switch
  off in Settings);
- **withdraw consent** at any time (notifications in your phone's settings; analytics and ads in Settings → Privacy),
  without affecting earlier processing;
- **lodge a complaint** with a supervisory authority — in the Czech Republic: *Úřad pro ochranu osobních údajů*,
  Pplk. Sochora 27, 170 00 Praha 7, www.uoou.gov.cz — or the authority in your EU country.

We answer requests within one month. We may ask you to confirm your identity (for example by writing from the email of
your account).

**Deleting your account** removes your profile and all data linked to it from our database at once (we only keep an
irreversible hash proving that a deletion happened). Opponents' battle history keeps a "Deleted user" entry without
your name. Backups at our hosting provider are overwritten within 30 days. Deleting the account **does not cancel an
App Store or Google Play subscription** — cancel it in your store account.

## 9. Age

You must be **at least 16** to create a Pushly account. We ask for your birth year and do not let younger people
sign up. The alarm itself works without an account. If you believe a child under 16 has an account, write to us and
we will delete it.

## 10. Security

All connections are encrypted (TLS). Database access rules make sure you can only read your own private data; every
competitive result is calculated on our servers; workout logs are signed by your device; secrets are kept out of the
app. No system is perfectly secure — if a breach affects you in a way that creates a high risk, we will tell you.

## 11. Data on your phone

The app keeps your alarms, settings and recent sessions on your phone so the alarm works offline. Sign-in tokens are
stored in the phone's secure storage (Keychain / Android Keystore). Deleting the app removes this data from the phone.

## 12. Changes

We may update this policy when the app changes. We will show important changes in the app before they take effect. The
date at the top shows the current version.

## 13. Contact

Daniel Oujeský — **dany.oujesky@gmail.com**
