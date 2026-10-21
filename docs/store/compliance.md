# Store compliance answers (P9-05)

Answers for the App Store Connect and Google Play Console forms. They match `docs/legal/privacy-policy.md`
(effective 21 Oct 2026) and what the code actually sends. **Update both this file and the policy when a feature
that collects data ships** (marked *later* below: ads, analytics, crash reports, Pro, video battles, review clips).

## URLs (GitHub Pages, workflow `pages.yml`)
| Field | URL |
|---|---|
| Privacy Policy (both stores) | https://danoujesky.github.io/Pushly---PushUp-Wars/privacy.html |
| Terms of Use / EULA link in the description | https://danoujesky.github.io/Pushly---PushUp-Wars/terms.html |
| Support URL (App Store) / website (Play) | https://danoujesky.github.io/Pushly---PushUp-Wars/support.html |
| Account deletion URL (Play: Data safety → Data deletion) | https://danoujesky.github.io/Pushly---PushUp-Wars/delete-account.html |
| Contact email | dany.oujesky@gmail.com |

App Store: keep Apple's **standard EULA** (our Terms of Use add the rest and refer to it). Once Pro ships, the
paywall and the App Store description must show the Terms and Privacy links (guideline 3.1.2).

## Apple — App Privacy ("nutrition label")
Tracking: **No** (no ATT tracking today; revisit when AdMob personalised ads start).

| Data type | Collected | Linked to user | Tracking | Purposes |
|---|---|---|---|---|
| Contact Info → Email Address | Yes | Yes | No | App Functionality |
| Health & Fitness → Fitness | Yes (reps, sessions, wake results) | Yes | No | App Functionality |
| User Content → Gameplay Content | Yes (battles, trophies, leaderboards) | Yes | No | App Functionality |
| User Content → Other User Content | Yes (username, clan names, clan chat) | Yes | No | App Functionality |
| Identifiers → User ID | Yes | Yes | No | App Functionality |
| Identifiers → Device ID | Yes (App Attest key id, push token) | Yes | No | App Functionality |
| Other Data | Yes (birth year, country, time zone, anti-cheat angle trace) | Yes | No | App Functionality |
| Diagnostics → Crash Data | *later* (Sentry) | No | No | App Functionality |
| Usage Data → Product Interaction | *later* (PostHog, consent) | Yes | No | Analytics |
| Purchases → Purchase History | *later* (Pro) | Yes | No | App Functionality |
| Identifiers → Device ID + Usage Data → Advertising Data | *later* (AdMob) | per consent | per ATT | Third-Party Advertising |

Not collected: photos or videos (camera frames stay on the device; live battle video is relayed in real time and not
stored, which Apple does not count as collection), precise/coarse location, contacts, browsing history.

## Apple — age rating
New questionnaire (2025): user-generated content **Yes**, messaging and chat **Yes**, unrestricted web access No,
gambling/loot boxes No, contests No, medical info No, violence/sexual content None. Pick the **16+** rating so it
matches our minimum account age (doc 16 §2, D-015).

## Google Play — Data safety
- Collects data: **Yes**. Shares data with third parties: **No** (processors acting for us don't count as sharing).
- Encrypted in transit: **Yes**. Users can request deletion: **Yes** — in the app and at the deletion URL above.
- Independent security review: No.

| Category → type | Collected | Optional? | Purposes |
|---|---|---|---|
| Personal info → Email address | Yes | Required for an account (the alarm works without) | Account management, App functionality |
| Personal info → User IDs | Yes | Required for an account | Account management, App functionality |
| Personal info → Other info (username, birth year, country) | Yes | Required for an account | Account management, App functionality |
| Health and fitness → Fitness info | Yes | Required for an account | App functionality |
| Messages → Other in-app messages (clan chat) | Yes | Optional | App functionality |
| App activity → Other actions (battles, friends, kudos) | Yes | Required for an account | App functionality |
| Device or other IDs | Yes (integrity key, push token) | Required for an account | App functionality, Fraud prevention, security and compliance |
| App info and performance → Crash logs | *later* (Sentry) | — | Analytics |
| App activity → App interactions | *later* (PostHog, consent) | Optional | Analytics |
| Financial info → Purchase history | *later* (Pro) | Optional | App functionality |
| Device or other IDs (advertising ID) | *later* (AdMob) | per consent | Advertising or marketing |

Photos and videos: **not collected** (processed on device only; live video is not stored).

## Google Play — other declarations
- **Target audience and content:** ages **16–17 and 18+** only (not designed for children; no Families policy).
- **Content rating (IARC):** users can interact / exchange messages: Yes; shares location: No; digital purchases:
  later (Pro); ads: later. Expected result Teen / PEGI 12–16 depending on the questionnaire.
- **Ads:** "No" until AdMob ships, then "Yes".
- **Health apps declaration:** fitness tracking, not medical.
- **Account deletion:** in app (Profile → Account & data) + web URL above.
- Exact alarm, full-screen intent, foreground service, camera: see `listing.md`.

## In-app (both platforms, done 21 Oct 2026)
- Welcome screen: health notice + "By tapping Get started you agree to the Terms of Use and the Privacy Policy"
  with links; Skip jumps to that page; the accepted version (`LegalLinks.version`) is stored on the device.
- Profile → Help & support, Terms of Use, Privacy Policy, Community Guidelines.
- Account & data → ghost recordings toggle (objection; off deletes recordings), data export, account deletion.
