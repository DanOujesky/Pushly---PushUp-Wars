# 01 — Product vision

## Elevator pitch
**Pushly turns your alarm clock into a push-up arena.** Your alarm keeps ringing until the camera sees you do your push-ups. Then you take the same push-ups into live battles with friends and strangers, climb leaderboards, and fight weekly Clan Wars.

## Problem
- People snooze. Waking up on time and starting the day with movement is hard.
- Home fitness apps are lonely and easy to fake (self-reported counts).
- Existing "mission alarms" (math problems, QR scans) wake you up but give nothing back afterwards.

## Solution pillars
1. **Unskippable wake-up** — a configurable alarm whose "dismiss" is a verified set of push-ups.
2. **Trustworthy counting** — on-device AI that counts only real, full-range push-ups and is hard to cheat. Fair competition is the whole product; if counts can be faked, leaderboards are worthless.
3. **Competition & community** — 1v1 live battles, global/friends leaderboards, clans and weekly Clan Wars.
4. **Visible progress** — beautiful, colorful stats that make users proud and want to share.

## Target users
- **Primary:** 16–30, students and young professionals, competitive, social, phone-first, want to wake up earlier / get stronger.
- **Secondary:** fitness enthusiasts who want a verified push-up log and challenges with friends.
- Launch market: global, English UI. Early community seeding in Czechia/Slovakia (founder's network).

## Product principles
1. **The alarm never fails.** Reliability > features.
2. **Fair or nothing.** Every competitive number is server-validated. No pay-to-win, ever.
3. **Fast to the camera.** From alarm ring to counting reps in ≤ 3 taps and ≤ 3 seconds.
4. **Celebrate effort.** Every session ends with a reward moment (animation, stats delta, streak).
5. **Respect the morning.** No ads, no upsells, no social noise during the wake flow.
6. **Private by default.** Video stays on the phone. Profiles are visible only to the extent the user chooses.

## Business model
- 100 % free core game.
- Phase 1: ads (AdMob) in non-critical places with strict caps.
- Phase 2: **Pushly Pro** subscription — removes ads, adds cosmetic and comfort extras (themes, alarm sounds, advanced stats, streak freezes, clan cosmetics). See doc 13.

## Success metrics (first 6 months after launch)
| Metric | Target |
|---|---|
| Alarm reliability (scheduled alarms that actually rang) | ≥ 99.5 % |
| Rep counting accuracy vs. human count on test set | ≥ 98 % (no false positives on "cheat" vectors) |
| D1 / D7 / D30 retention | 40 % / 20 % / 10 % |
| Wake Challenge enrolment of new users | ≥ 50 % |
| Avg. wake challenges completed per enrolled user per week | ≥ 4 |
| Users with ≥ 1 friend | ≥ 35 % |
| Battles per DAU per day | ≥ 0.8 |
| Pro conversion (once launched) | 2–4 % of MAU |

## Out of scope (v1)
- Other exercises (squats, sit-ups) — architecture must allow them later (`exercise_type` everywhere), but v1 ships push-ups only.
- Apple Watch / Wear OS apps.
- Web app.
- Group battles with > 2 players (v2).
- Chat beyond clan chat (no DMs in v1).
