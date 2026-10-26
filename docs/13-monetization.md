# 13 — Monetization (ads → Pushly Pro)

> **Built (D-073, D-074, 2026-10-25):** banners (`stats_banner`, `ranks_banner`, `clan_banner`),
> `battle_results_interstitial`, UMP consent without ATT, Pushly Pro paywall with monthly / yearly plans, perks: no
> ads, 2 streak freezes a month, PRO badge, **5 profile frames**, **Pro sound pack (4 alarm
> tones)**, **8 Pro clan emblems**. Paywall reasons: profile, remove_ads, sound, frame, emblem (ghost battles removed, D-076). Not
> built: rewarded placements (Q-12), custom sound import, advanced stats, themes, victory animations, lifetime.

Rules that never change:
- The core game is **100 % free**.
- **No pay-to-win**: nothing purchasable affects reps, trophies, matchmaking, clan war scores or leaderboards.
- No ads in the morning flow or any camera context (CLAUDE.md §4.5).

## 1. Phase A — ads (launch)
SDK: Google Mobile Ads (AdMob) + **UMP** (User Messaging Platform) for GDPR consent (EU/UK/CH) and the iOS **ATT** prompt (asked once, after the user's 3rd completed session, with a pre-prompt; if denied → non-personalised ads).

All ad calls go through `AdsGate` (ShopFeature). `AdsGate.canShow(placement, context)` returns false when **any** of these is true:
- user is Pro;
- a wake flow is active or ended < 10 min ago;
- a camera session or battle is active, in lobby, or in matchmaking;
- the alarm editor or alarm health screens are visible;
- the user is in onboarding or has < 2 completed sessions total;
- frequency caps exceeded (below).

| Placement | Format | Where | Cap |
|---|---|---|---|
| `battle_results_interstitial` | interstitial | after **closing** the results screen of a battle (never before seeing the result) | max 1 per 3 battles, min 4 min apart, max 6 / day |
| `ranks_banner` | adaptive banner | bottom of Ranks tab list | — |
| `stats_banner` | adaptive banner | bottom of Stats dashboard (below the charts) | — |
| `clan_banner` | adaptive banner | clan discovery list only (not chat) | — |
| `rewarded_streak_freeze` | rewarded video | "Watch an ad to earn a streak freeze" (max 1 / week, only if user has 0 freezes) | 1 / week |
| ~~`rewarded_extra_ghost`~~ | — | removed with ghost battles (D-076) | — |

Global cap: max **8 interstitial + rewarded impressions per day** per user. Preload interstitials only when allowed; never show an ad within 2 s of a tap (accidental clicks).
Ad unit IDs per platform/env in config; test IDs in debug/staging (CLAUDE.md §4.6: no real IDs in repo — inject via CI secrets).

## 2. Phase B — Pushly Pro (after launch; roadmap Phase 10)
Implementation: **RevenueCat** (StoreKit 2 + Google Play Billing), entitlement id `pro`. Offerings configured remotely.

| Product | Price (suggested, adjust per region in stores) |
|---|---|
| `pro_monthly` | €2.99 / month |
| `pro_yearly` | €19.99 / year (7-day free trial) |
| `pro_lifetime` | €49.99 one-time (optional, A/B) |

Pro benefits (comfort & cosmetic only):
- No ads anywhere.
- Premium alarm sound pack + import unlimited custom sounds (free: 1 custom sound).
- Up to 2 streak freezes refilled monthly (free users can earn them).
- Advanced stats: year view, form deep-dive charts, CSV export, compare with friends.
- Cosmetics: Pro profile frame, animated badge, app themes (color accents), extra clan emblems, battle victory animations.

Paywall: shown only from explicit entry points (Profile → Pro, "Remove ads" button on banners, Pro-locked feature tap). **Never** after the wake flow or a lost battle. Honest copy, clear trial terms, restore purchases, links to terms & privacy (store requirements).

Server: `revenuecat-webhook` → `entitlements` → `profiles.is_pro` (used e.g. for monthly freeze refill). Client reads RevenueCat `CustomerInfo` for instant UI; server is authoritative for server-side perks.

## 3. "Small extras" (optional, later)
- One-time cosmetic packs (frames, victory animations) — cosmetic only, purchasable without Pro.
- No loot boxes, no randomised paid items (CLAUDE.md §10).
