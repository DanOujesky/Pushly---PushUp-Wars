# Store listing drafts (P9-05)

## Name / subtitle
- App Store name: **Pushly – PushUp Wars** (30 chars max) · Subtitle: **Alarm that needs push-ups** (30)
- Google Play title: **Pushly – PushUp Wars** · Short description (80): **The alarm that only stops after real push-ups. Battle friends, climb the ranks.**

## Description (both stores)
Can't get out of bed? Pushly's alarm keeps ringing until you've done your push-ups — and the camera counts every rep.

WAKE-UP CHALLENGE
• Set how many push-ups it takes to stop the alarm (5 to 100)
• Modes: ring until done, beat the clock, sprint, sets, escalation
• The camera counts only full, clean reps — the video never leaves your phone
• Keep your streak alive every morning

BATTLES
• 1v1 push-up battles against friends or players worldwide
• Max reps, speed and endurance modes
• Trophies, leagues and monthly seasons — fair matchmaking, no pay-to-win

CLANS & FRIENDS
• Team up in clans of up to 30 and win the weekly Clan War
• Friends feed, kudos and friends leaderboards

STATS
• Daily push-ups, best set, wake consistency, all-time totals, activity heatmap
• 44 achievements and levels

Free to play. Your camera video is analysed on your device and never stored.

## Keywords (App Store, 100 chars)
pushup,push up,alarm,wake up,fitness,workout,challenge,battle,streak,habit,morning,counter,clan

## Review notes (App Store)
- Demo account: `[email]` / sign-in link — `[how to get the code for review]`.
- How to test the alarm: Wake tab → Add alarm → set 1 minute from now → when it rings, tap the alarm, place the
  phone ~2 m to your side in landscape, do 5 push-ups (or use the attached video).
- Camera: frames are processed on device with MediaPipe; no video is uploaded or recorded.
- AlarmKit is the core feature (wake-up challenge).
- User-generated content: clan chat (profanity filter, report, block, leaders delete messages), usernames
  (filtered), live video battles (ranked = no microphone, report, block). Contact: dany.oujesky@gmail.com.
- Account deletion: Profile → Account & data → Delete account.

## Google Play declarations
- Exact alarm: `SCHEDULE_EXACT_ALARM` — alarm clock is the core function.
- Full-screen intent: alarm ringing screen.
- Foreground service: alarm ringing (`[type per D-018]`) — demo video `[link]`.
- Camera: push-up counting on device.
- Data safety: matches docs/legal/privacy-policy.md §3 (email, username, fitness data, app activity, device ids
  for integrity; no data sold; deletion in app and at
  https://danoujesky.github.io/Pushly---PushUp-Wars/delete-account.html). Full answers: `compliance.md`.
- Content rating and target audience: see `compliance.md`.
