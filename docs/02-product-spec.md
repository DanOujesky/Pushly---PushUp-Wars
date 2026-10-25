# 02 — Product specification

This document describes **what the user sees and can do**. Technical details live in docs 04–16; this doc links to them.
Each requirement has an ID (`PS-xx`) so tasks and tests can reference it.

---

## 1. Navigation

Bottom tab bar, 5 tabs (icons + labels):

| Tab | Purpose |
|---|---|
| **Wake** (home) | Wake Challenge status, next alarm, streak, quick "Train now" |
| **Battle** | Start / accept battles, battle history, current trophies & league |
| **Clan** | Your clan, Clan War status, clan chat; or clan discovery if not in one |
| **Ranks** | Leaderboards (global / country / friends / clan) |
| **Profile** | Stats & progress, achievements, friends, settings, Pro |

A persistent **"Do push-ups"** floating button is **not** used (keeps the wake tab focused); free training is reachable from Wake and Profile.

---

## 2. Onboarding (first launch)

PS-01. Splash → 3 short value screens (swipeable, skippable): "Your alarm. Your push-ups." / "Battle anyone, live." / "Climb with your clan."

PS-02. **Account:** Sign in with Apple (iOS, required by App Store if other social logins exist), Sign in with Google (both platforms), or email magic link / OTP. No passwords.
- Guest mode is allowed for the **alarm only** (local, offline). Anything competitive requires an account. Guest data (local wake history) is merged on sign-up.

PS-03. **Profile setup:** username (unique, 3–20 chars, `[a-zA-Z0-9_.]`, profanity-filtered server-side), avatar (preset avatars + optional photo), country (pre-filled from locale, editable), birth year (age gate: **16+**, see doc 16).

PS-04. **Calibration & first push-ups** (the "aha" moment): pre-permission explainer → camera permission → phone placement guide (animated) → user does 3 push-ups → app shows "3 ✓" with confetti. This also stores per-user calibration (doc 05 §6).

PS-05. **Wake Challenge offer:** "Want Pushly to wake you up?" → alarm setup wizard (§4) → alarm permission explainer → OS permission(s). User may skip; the Wake tab then shows a big "Set up your wake-up" card.

PS-06. Notification permission requested **only** when the user first does something that benefits from it (adds a friend, joins a clan, sends a battle invite), never during onboarding.

---

## 3. Wake tab (home)

PS-10. Header: greeting, current **wake streak** 🔥 (days in a row with a successful wake challenge), Pro badge if any.

PS-11. **Next alarm card:** time, weekday, mode + target ("Ring Until Done · 20 push-ups"), countdown ("in 7 h 12 min"), toggle to skip only the next occurrence ("Skip tomorrow"), tap → Alarm editor.

PS-12. **Health check banner** (red/amber) if anything threatens the alarm: alarm permission denied, exact-alarm permission revoked (Android), notifications blocked, Focus/DND blocking (Android), battery optimisation restricting the app (Android), low storage for sounds, camera permission denied. Each banner has a one-tap fix (deep link to the right settings page). See doc 04 §8.

PS-13. **This week strip:** 7 day circles (Mon–Sun) — green = beaten, red = failed, grey = no alarm, outlined = upcoming.

PS-14. Quick actions: **Train now** (free session, counts to totals/clan, not to wake streak), **Test my alarm** (fires a real alarm in 10 s using the current settings, result not counted).

PS-15. **Today summary:** push-ups today, clan contribution today, global rank for wake challenge (e.g. "#1,284 this month").

---

## 4. Alarm editor (full detail in doc 04)

PS-20. The user can create **multiple alarms**; each alarm has its own schedule and its own challenge mode. Only alarms flagged **"Counts for Wake Challenge"** (max **one per local calendar day** — the earliest enabled one counts) affect streak and leaderboards; others are "practice alarms".

PS-21. **Schedule types per alarm:**
- *Weekly*: pick weekdays; **each weekday can have a different time** (e.g. Mon 6:30, Tue 7:15, Sat 9:00).
- *One-off*: specific date + time.
- *Overrides*: on top of a weekly alarm the user can set a different time for a specific date ("Thursday 23 Oct → 5:40") or skip a specific date. Overrides show in a mini calendar.
- Quick "Skip next" and "Pause for N days" (vacation mode, 1–30 days; streak is **frozen**, not broken, during a pause — max 14 paused days per calendar month to prevent abuse).

PS-22. **Challenge modes** (picker with illustrations):
| Mode | Rule | Fail condition |
|---|---|---|
| **Ring Until Done** | Alarm rings until target reps are completed (target 5–100) | User stops the alarm without completing, or doesn't complete within 30 min |
| **Beat the Clock** | After ringing starts, complete target reps within the time window (30 s – 10 min) | Window expires before target |
| **Sprint** | Max reps in a fixed window (30/60/120 s); success if ≥ minimum (user sets minimum, ≥ 5) | Below minimum |
| **Sets** | N sets × M reps with rest timer (e.g. 3 × 10, 45 s rest); alarm rings again before each set | Any set missed |
| **Escalation** | Starts at target X; every snooze adds +Y reps (default +5) and snooze lasts Z min (default 5); max 3 snoozes | > 3 snoozes or not completed |

PS-23. **Ringing options:** sound (bundled library of ≥ 12 sounds; Pro adds more), **import your own sound** (both platforms: Android plays the file directly; iOS AlarmKit only plays files from the app bundle or `Library/Sounds`, so the app converts the imported file to `.caf` and copies it there — the maximum allowed length must be verified in the Phase 2 AlarmKit spike and the UI trims to it), volume ramp (off / 30 s / 60 s) and vibration pattern (**Android only** — iOS AlarmKit controls volume/vibration itself, so these controls are hidden on iOS), label text ("Get up, champion"; shown as the alarm title).

PS-24. **Pre-alarm options:** gentle pre-alarm notification N min before (off by default), bedtime reminder (notification at chosen time, e.g. 8 h before alarm).

PS-25. **Difficulty adjustments** shown live: "Your average for this target: 42 s".

PS-26. Editing an alarm less than **15 minutes** before its next ring does not change whether that occurrence counts for the Wake Challenge (anti-gaming: no lowering 50 → 5 at 6:59). The edit applies to the next occurrence; the app explains this inline.

---

## 5. Wake flow (when the alarm rings)

PS-30. Alarm rings (system alarm UI on iOS; full-screen Pushly ring screen on Android). Primary action: **"Start push-ups"** → opens the camera screen directly (target ≤ 3 s to first frame analysed).

PS-31. **Camera screen (wake variant):** big rep counter, target ("12 / 20"), mode timer if applicable, body-in-frame indicator (green outline when fully visible), live form hints ("Go lower", "Keep your body straight"), the alarm sound continues at reduced volume until done in *Ring Until Done* (Android) / is re-triggered by follow-up alarms on iOS (doc 04 §5.2).

PS-32. **Completion:** sound stops instantly, success animation, summary card: reps, time, form score, streak +1, rank change, clan contribution. Buttons: "Share" (generates image card), "Done". **No ad.**

PS-33. **Failure:** calm screen, "Challenge lost today" + streak reset (or streak-freeze consumed if user has one) + "Try a Train now session?" — never shaming copy.

PS-34. The wake flow works **offline**. Results are stored locally and synced later; server validates timestamps against the signed log (doc 06).

---

## 6. Battles (full detail in doc 07)

PS-40. Battle tab is one lobby screen without scrolling (D-071): trophies + league emblem, mode picker + a big **BATTLE** button (Quick match, random opponent, ranked), tiles for **Friends** (always friendly), **Practice** (bots, ghosts) and **History**; open invites show above the button.

PS-41. **Modes:** *Max Reps* (most reps in 60 s), *Best of 3* (three rounds of max-reps-in-one-set, no pausing > 2 s at top; best of 3 rounds), *Speed* (first to N reps), *Turns* (alternate one rep each; first to miss the 5 s turn window or break form loses), *Endurance* (unlimited reps; a pause > 3 s in top or bottom position ends your set; highest total wins).

PS-42. Split-screen live video (top: opponent, bottom: you; or side-by-side in landscape), both counters huge, countdown 3-2-1, haptics on each rep, opponent rep pops.

PS-43. Results screen: winner, reps each, trophies ±, rematch (friendly only), report player.

PS-44. Ranked battles only with **random** opponents in Quick Match. Battles against friends are always friendly and never change trophies (D-071).

---

## 7. Clans (full detail in doc 09)

PS-50. Create (name, tag 3–5 chars, badge from presets, description, join policy: open / request / invite-only, min trophies, country optional) or join a clan. Max **30 members**. One clan per user.

PS-51. Clan home: members list with today's & this week's push-ups, roles (Leader, Co-leader, Elder, Member), **Clan War card** (opponent, live score, time left), clan chat, clan stats chart.

PS-52. **Clan Wars:** weekly, automatic matchmaking of clans with similar strength; score = all verified push-ups of members during the war week (wake + battles + training), with anti-farming caps (doc 09 §3). Winner gets clan trophies; members get a cosmetic war chest (badges/frames — never competitive advantage).

---

## 8. Ranks tab (full detail in doc 08)

PS-60. Segmented control: **Wake** / **Battles** / **Total push-ups** / **Clans**.
PS-61. Scope filter: Global / Country / Friends / My clan (where it makes sense).
PS-62. Period filter: Today / This week / This month / Season / All-time.
PS-63. Own row always pinned at the bottom if not visible. Top 3 have animated podium.

---

## 9. Profile & stats (full detail in doc 10)

PS-70. Header: avatar, username, clan tag, league badge, country flag, level (XP from all activity).
PS-71. **Stats dashboard** with beautiful charts: daily push-ups (bar), cumulative (area), wake-up time consistency (scatter/heatmap), best set over time (line), tempo & form score trends, calendar heatmap (GitHub-style), personal records.
PS-72. Achievements (badges grid), friends list, battle record (W/L, win-rate by mode).
PS-73. Settings: account, privacy (profile visibility: public / friends / private; show in leaderboards yes/no — opting out hides the name as "Anonymous athlete" but keeps scores), notifications, units, alarm health check, data export, delete account, Pro management, legal.

---

## 10. Free training

PS-80. "Train now": choose *Free* (count until stop), *Target* (N reps), *Timed* (N s). Counts towards totals, clan war, achievements, but **not** wake streak or wake leaderboard.

---

## 11. Global rules

PS-90. All competitive numbers display as "pending" (subtle clock icon) until the server has validated them; they then animate to final values.
PS-91. All lists support pull-to-refresh; all screens have empty, loading (skeletons) and error states.
PS-92. Haptics: light tap per rep, success notification haptic on completion, warning haptic on form error.
PS-93. Accessibility: full VoiceOver/TalkBack; the camera screen announces rep counts ("Seven") via speech and has an optional audio-only coach mode.
PS-94. Sound: every rep plays a short "tick" (toggleable); completion jingle.
