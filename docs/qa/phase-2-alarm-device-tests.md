# Phase 2 — alarm tests on real phones

CI already proves the logic (shared vectors, scheduler unit tests on both platforms, 71 database assertions) and
renders the iOS screens in the simulator. What only a real phone can show is listed here. Results go into `docs/19-decisions-log.md`
(D-012, D-018, D-019) and `docs/STATUS.md`.

Use **"Test alarm (10 s)"** in the alarm editor for quick runs; use a real alarm 2–3 minutes ahead for the rest.

## Android (debug APK from the `android` workflow — app id `app.pushly.debug`)
| # | Test | Expected | Doc |
|---|---|---|---|
| A1 | Save the first alarm | "Make sure it rings" explainer opens; Notifications, Alarms & reminders, Full-screen alarm can be allowed | P2-10 |
| A2 | Test alarm, phone locked | Full-screen ring screen over the lock screen, sound on the alarm stream, alarm icon in the status bar before it rings | AT-ALM-02 |
| A3 | Same with silent / vibrate / Do Not Disturb on | Still rings | AT-ALM-02 |
| A4 | Press volume buttons and Back while ringing | Volume changes, alarm keeps ringing, Back does nothing | doc 04 §6.3 |
| A5 | Start push-ups → "Back to the alarm" | Ring screen returns at full volume | doc 04 §6.3 |
| A6 | Start push-ups → "Complete (debug)" | Sound stops at once, notification disappears | AT-ALM-06 |
| A7 | Hold "Give up" for 3 s | Alarm stops; shorter hold does nothing | doc 04 §6.3 |
| A8 | Escalation mode → Snooze | Rings again after the snooze, target +N | doc 04 §3 |
| A9 | Swipe Pushly away from recents, alarm in 2 min | Still rings | AT-ALM-04 |
| A10 | Reboot, **don't unlock**, alarm in 3 min | Rings before unlock | AT-ALM-03 |
| A11 | Revoke "Alarms & reminders", return to the app | Red banner on the Wake tab within a second | AT-ALM-09 |
| A12 | Turn notifications off for Pushly | Red banner | AT-ALM-09 |
| A13 | Leave an issue unfixed with an alarm tomorrow morning | "Your alarm may not ring" notification ~21:00 (if notifications allowed) | doc 04 §8 |
| A14 | Sign in on a second phone | Alarms appear there (restore via `sync_alarms`) | P2-09 |

Record the phone model, Android version and whether the ring service started as `systemExempted` or fell back
(D-018), and whether the OEM (Samsung/Xiaomi/…) killed anything.

## iOS (needs a signed build: TestFlight or Xcode on a Mac — not possible from CI yet)
| # | Test | Expected | Doc |
|---|---|---|---|
| I1 | Save the first alarm → Allow | iOS AlarmKit permission sheet; Wake tab without the red banner | P2-10 |
| I2 | Test alarm, phone locked, Silent mode + Focus on | System alarm UI with **Stop** and **Start push-ups**, Pushly tint, rings through Silent/Focus | AT-ALM-02 |
| I3 | Press Stop on a "Ring until done" alarm | Rings again within ≤ 2 min ("Still in bed? …") until the push-ups are done | AT-ALM-05 |
| I4 | Press Start push-ups | App opens straight into the wake session (sound continues quietly) | doc 04 §5.1 |
| I5 | In the session press "Complete (debug)" | All further nags cancelled (none ring for 10 min) | AT-ALM-06 |
| I6 | Open the session, then kill the app from the app switcher | A nag rings within ~90 s (dead-man's switch) | doc 04 §5.2 |
| I7 | Touch the bottom edge of the lock-screen alarm instead of the buttons | Note what happens; a nag must still ring within 2 min | doc 04 §5.2 quirk |
| I8 | Schedule 10 alarms with different times per day | How many AlarmKit alarms exist (Settings may show it); any error banners? → per-app limit | D-019 |
| I9 | Reboot the phone, alarm in 3 min | Rings | AT-ALM-03 |
| I10 | Update the app (install a newer build) with alarms set | Alarms still ring | D-019 |
| I11 | Turn Alarms off in Settings › Pushly | Red banner after returning | AT-ALM-09 |
| I12 | Live Activity / Dynamic Island while an alarm is pending | Shows "N push-ups to stop it" | doc 04 §5.1 |
