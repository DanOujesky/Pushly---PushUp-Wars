# 04 — Alarm system

> Reliability is the #1 requirement of the whole product (CLAUDE.md §4.4). Read this doc completely before touching any alarm code.

## 1. Concepts

- **Alarm** (`AlarmSchedule`) — a user-defined alarm: schedule + challenge mode + sound.
- **Occurrence** — one concrete ring of an alarm on a local date. ID: `"{alarmId}:{yyyy-MM-dd}"` (local date of the *scheduled* time).
- **Wake attempt** — the record of what happened with an occurrence that counts for the Wake Challenge.
- **Challenge alarm** — an alarm with `countsForChallenge = true`. For each local date, only the **earliest enabled** challenge-alarm occurrence counts. A user can have many alarms, but the Wake Challenge sees at most one occurrence per day.

## 2. Data model (client, mirrored on server in `alarm_schedules`)

```jsonc
// shared/contracts/alarm-schedule.schema.json (summary)
{
  "id": "uuid",
  "version": 7,                      // incremented on every edit (optimistic concurrency for sync)
  "label": "Get up, champion",
  "enabled": true,
  "countsForChallenge": true,
  "kind": "weekly" | "oneOff",
  "weekly": {                        // present when kind = weekly
    "mon": "06:30", "tue": "07:15", "wed": null, "thu": "06:30",
    "fri": "06:30", "sat": "09:00", "sun": null    // null = no alarm that weekday
  },
  "oneOff": "2026-10-23T05:40",      // local date-time, present when kind = oneOff
  "overrides": [                     // only for weekly
    { "date": "2026-10-23", "time": "05:40" },
    { "date": "2026-10-25", "skip": true }
  ],
  "pause": { "from": "2026-12-24", "to": "2026-12-31" } | null,
  "mode": {
    "type": "ringUntilDone" | "beatTheClock" | "sprint" | "sets" | "escalation",
    "targetReps": 20,                // ringUntilDone, beatTheClock, escalation (start)
    "windowSeconds": 60,             // beatTheClock, sprint
    "minimumReps": 10,               // sprint
    "sets": 3, "repsPerSet": 10, "restSeconds": 45,   // sets
    "snoozeAddsReps": 5, "snoozeMinutes": 5, "maxSnoozes": 3  // escalation
  },
  "sound": { "id": "bundled.rooster_rush" | "custom.<uuid>", "rampSeconds": 30 /* Android */ },
  "vibration": "pulse" | "heartbeat" | "none",     // Android only
  "preAlarmMinutes": null | 5..30,
  "bedtimeReminderMinutes": null | 360..600,
  "updatedAt": "2026-10-19T13:00:00Z"
}
```

### Validation rules (enforce in client UI **and** server)
| Field | Rule |
|---|---|
| `targetReps` | 5–100 |
| `windowSeconds` | beatTheClock 30–600; sprint ∈ {30, 60, 120} |
| `minimumReps` | 5–100 |
| `sets` × `repsPerSet` | sets 2–5, repsPerSet 5–50, restSeconds 15–180 |
| escalation | `snoozeAddsReps` 1–20, `snoozeMinutes` 1–10, `maxSnoozes` 1–5 |
| times | `HH:mm`, 24h, minute precision |
| overrides | date must be in the future, max 60 overrides per alarm |
| pause | max 30 days per pause; server enforces ≤ 14 frozen days per calendar month for streak purposes |
| alarms per user | max 20 |

## 3. Challenge modes — exact rules

Common to all modes:
- `T0` = scheduled ring time of the occurrence (from the schedule snapshot, not from when the phone actually rang).
- **Completion deadline** = `T0 + 30 min` for every mode (mode rules may be stricter).
- Only reps produced by `RepEngine` in a camera session linked to this `occurrenceId` count.
- Result states: `succeeded`, `failed`, `missed` (no camera session started before deadline), `skipped` (user skipped in advance), `paused`, `void` (system issue proven, e.g. alarm never fired because OS permission was revoked — not counted either way; see §8).

| Mode | Success condition | Notes |
|---|---|---|
| **ringUntilDone** | `targetReps` reached before deadline | Alarm sound continues (Android) / re-fires via nag chain (iOS) until success |
| **beatTheClock** | `targetReps` reached within `windowSeconds` measured from **T0** (the moment the alarm rings). Example: window 60 s, target 10 → the 10th rep must happen before `T0 + 60 s` | The countdown is shown on the ring screen and the Live Activity. The editor warns when `windowSeconds / targetReps < 3 s` ("very hard: includes getting out of bed"). If the device rang late (OS delay, proven by the ring timestamp in the log), the window starts at the actual ring time |
| **sprint** | reps in `windowSeconds` ≥ `minimumReps`; window starts at the first frame where the body is fully visible in the push-up start (plank) position, auto-start after a 3-2-1 countdown | Must start before deadline. Score = reps (used in leaderboards as "wake sprint best") |
| **sets** | every set reaches `repsPerSet`; each set must start within `restSeconds + 30 s` after the previous set ended | Between sets the alarm re-rings at rest end (in-app sound if app is foreground, OS alarm otherwise) |
| **escalation** | final target reached before deadline, where final target = `targetReps + snoozes × snoozeAddsReps` | Snooze is only offered in this mode. After `maxSnoozes` the snooze button disappears |

## 4. Occurrence computation (pure function, shared spec)

`func occurrences(schedule, fromInstant, timeZone, horizonDays) -> [Occurrence]` — **pure**, deterministic, implemented on both platforms and tested against `shared/test-vectors/alarm-occurrences/*.json`.

Rules:
1. Wall-clock semantics: alarm times are local times in the **device's current time zone**. If the user travels, alarms follow the new local time (like the system Clock app). Re-compute on time-zone change.
2. For each local date in `[today, today + horizonDays]`:
   - if `pause` covers the date → no occurrence (state `paused`);
   - if an override exists for the date → use it (`skip` → no occurrence);
   - else weekly time for the weekday (or the one-off date-time).
3. **DST gap** (local time doesn't exist, e.g. 02:30 on spring-forward day): ring at the first valid minute after the gap (03:00).
4. **DST overlap** (time occurs twice): ring at the **first** instance.
5. Drop occurrences whose instant is ≤ `fromInstant`.
6. Occurrences are sorted by instant; `countsForChallenge` resolution (earliest per local date) happens in a separate pure function `challengeOccurrence(for date, allAlarms)`.

Test vectors must include: Europe/Prague spring forward (last Sunday of March) and fall back (last Sunday of October), America/New_York, Asia/Kolkata (UTC+5:30), Australia/Lord_Howe (30-minute DST), date-line travel, overrides on DST days, pause boundaries.

## 5. iOS implementation (AlarmKit)

### 5.1 Basics
- Requires **iOS 26+**. Add `NSAlarmKitUsageDescription` to Info.plist ("Pushly uses alarms to wake you up for your push-up challenge, even in Silent mode or Focus.").
- Request authorization via `AlarmManager.shared.requestAuthorization()` **after** the pre-permission explainer screen. If denied → health banner + the alarm cannot be scheduled (show it clearly, never pretend).
- AlarmKit alarms **break through Silent mode and Focus**, show on Lock Screen / Dynamic Island / StandBy.
- The system alert always has a **Stop button (required by AlarmKit)** plus one optional secondary button. We cannot remove Stop. Design around it (§5.2).
- Secondary button: **"Start push-ups"** with `secondaryButtonBehavior: .custom` and an App Intent (`StartWakeSessionIntent`, `openAppWhenRun = true`) carrying `occurrenceId`. Opens straight into the wake camera screen.
- Stop button label: **"Stop"**; its `stopIntent` = `AlarmStoppedIntent(occurrenceId)` which records the stop and (for ringUntilDone/escalation) keeps the nag chain alive.
- Sounds: bundled `.caf` files in the app bundle or files copied into `Library/Sounds` (custom imports). Use `AlertConfiguration.AlertSound.named(...)`.
- Countdown UI (beatTheClock window, sets rest, escalation snooze) uses a **Live Activity** in the Widget Extension — AlarmKit requires a Live Activity for any alarm that uses countdown presentation.
- `AlarmMetadata` struct `PushlyAlarmMetadata { occurrenceId, modeType, targetReps }` passed for the Live Activity UI.
- Tint color = brand primary (identifies Pushly alarms).

### 5.2 "Ring until done" on iOS — the nag chain
Because the user can always press Stop on the system alert, we emulate "rings until done":
1. For each counting occurrence we schedule the **main alarm** at `T0` and a **nag chain** of follow-up one-shot alarms at `T0 + 2, +4, +6 min` (titles: "Still in bed? 20 push-ups waiting").
2. Whenever app code runs for this occurrence (Stop intent, Start intent, app foreground), we **extend** the chain so there are always ≥ 3 pending nags, every 2 min, until the deadline `T0 + 30 min`.
3. While the wake camera session is active in the foreground, the app plays the alarm sound itself at reduced volume (`AVAudioSession` category `.playback`, mixes off) until success, and keeps a **dead-man's switch**: the next nag is always rescheduled to `now + 90 s`; if the app crashes or is closed, the nag fires.
4. On success → cancel all remaining nags for the occurrence immediately (`AlarmManager.shared.cancel(id:)`), stop the in-app sound.
5. On explicit **"Give up"** (button inside the app, confirmation dialog) → cancel nags, mark `failed`.
6. Escalation snooze uses AlarmKit's countdown/snooze behaviour for `snoozeMinutes`; the in-app target increases.

Known platform quirk to handle defensively: there are developer reports that touching the bottom area of the Lock Screen alert can dismiss an AlarmKit alarm **without** calling stopIntent or the secondary intent, leaving it in the `.alerting` state. Therefore:
- Never rely on intents being called. On every app launch/foreground, **reconcile**: read `AlarmManager.shared.alarms`, force-stop any alarm stuck in `.alerting` for > 2 min, and repair the nag chain for any occurrence still within its deadline.
- The pre-scheduled nags at +2/+4/+6 exist precisely so that a missed callback still re-rings.

### 5.3 Rolling scheduling window
Different times per weekday + date overrides + pauses are modelled cleanly as **one-shot fixed-date alarms**, scheduled in a rolling window:
- Window: next **7 days** of occurrences for all enabled alarms (+ nag chains for challenge occurrences).
- Re-fill the window on: app launch, app foreground, every alarm intent execution, schedule edits, time-zone/significant-time change notifications, `BGAppRefreshTask` (requested daily), and a daily **silent push** from the server (`content-available`, sent at 03:00 local time by cron) that wakes the app to refill.
- If the window would run out within 48 h and the app hasn't run (detected by the server: no refresh ack for 5 days), send a visible push: "Open Pushly so your alarms keep ringing".
- **Phase 2 spike must verify:** the maximum number of alarms AlarmKit allows per app, behaviour after device reboot, after app update, and after the app is offloaded. If the per-app limit is lower than our window needs, shrink the window (min 3 days) and reduce the nag chain to 2 pre-scheduled nags. Record results in the decisions log.

### 5.4 `AlarmScheduler` (iOS) contract
```swift
protocol AlarmScheduling: Sendable {
    func authorizationState() async -> AlarmAuthState
    func requestAuthorization() async -> AlarmAuthState
    func sync(schedules: [AlarmSchedule], now: Date) async throws -> SyncReport   // idempotent diff: desired vs. scheduled
    func startNagChain(occurrenceId: OccurrenceID, until deadline: Date) async
    func cancelNags(occurrenceId: OccurrenceID) async
    func reconcile(now: Date) async -> ReconcileReport
}
```
`sync` computes the desired set of OS alarms (IDs derived deterministically from occurrenceId + role, e.g. UUIDv5) and diffs against `AlarmManager.shared.alarms` — cancels extras, schedules missing ones. **Idempotent**: calling it twice changes nothing.

## 6. Android implementation

### 6.1 Permissions & manifest
- `SCHEDULE_EXACT_ALARM` (user-granted special access "Alarms & reminders"). Check `AlarmManager.canScheduleExactAlarms()`; if false → explainer → `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`. Listen for `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` and re-sync. (Revoking it cancels all our exact alarms — health banner must catch this.)
  - `USE_EXACT_ALARM` is restricted by Google Play policy to apps whose core function is an alarm clock or calendar. Decision: start with `SCHEDULE_EXACT_ALARM`; evaluate `USE_EXACT_ALARM` in the Play policy review before launch (decisions log D-012).
- `USE_FULL_SCREEN_INTENT` — on Android 14+ this is granted by default only to calling/alarm apps and requires a Play Console declaration. Check `NotificationManager.canUseFullScreenIntent()`; if false → explainer → `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`.
- `POST_NOTIFICATIONS` (Android 13+), `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `VIBRATE`, `CAMERA`, `FOREGROUND_SERVICE` + the type-specific FGS permission for the ring service (see 6.3).
- Request "ignore battery optimisations" only through an explainer when an OEM with aggressive killing is detected (Xiaomi, Huawei, Oppo, Vivo, OnePlus, Samsung) — link to dontkillmyapp-style instructions inside the app (our own copy).

### 6.2 Scheduling
- For each enabled alarm schedule **only the next occurrence** with `AlarmManager.setAlarmClock(AlarmClockInfo(triggerAt, showIntent), operationPendingIntent)`. `setAlarmClock` is exact, works in Doze, and shows the alarm icon in the status bar.
- Re-sync on: boot (`BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED` with direct-boot-aware storage for the schedule), `TIME_SET`, `TIMEZONE_CHANGED`, `MY_PACKAGE_REPLACED`, exact-alarm permission change, after every ring, after every edit, app start.
- Schedules are stored in Room **and** mirrored to a small direct-boot-aware file so alarms can be re-armed before the user unlocks after a reboot.
- Daily `WorkManager` periodic job (`AlarmIntegrityWorker`) verifies the next alarm is armed (`AlarmManager.getNextAlarmClock()` + our own record) and re-arms if not.

### 6.3 Ringing
1. `AlarmReceiver.onReceive` → start `AlarmRingService` as a foreground service immediately (type `systemExempted`, which Android allows for apps holding the exact-alarm permission; fallback `mediaPlayback` — verify on Android 14/15/16 in the Phase 2 spike and record in decisions log).
2. Service posts a high-priority `CATEGORY_ALARM` notification with **full-screen intent** → `RingActivity` (`showWhenLocked`, `turnScreenOn`), plays sound via `MediaPlayer`/`ExoPlayer` on `AudioAttributes.USAGE_ALARM` (rings even in silent/vibrate, respects user's alarm volume), applies volume ramp and vibration pattern, holds a partial wake lock.
3. `RingActivity` shows: time, label, mode + target, **"Start push-ups"** (big), and **Snooze** only in escalation mode. **There is no Stop button in ringUntilDone / beatTheClock / sets / sprint**. A small "Give up" link opens a confirmation (hold-to-confirm 3 s) → `failed`.
4. "Start push-ups" opens the camera inside the ring flow (`WakeCameraActivity`, also `showWhenLocked`); the service keeps playing at 30 % volume until success (ringUntilDone) or until the mode ends.
5. Hardware volume buttons lower volume but never stop the alarm. The service ignores `ACTION_SCREEN_OFF`.
6. If the user force-stops the app, Android stops everything — this is recorded as `missed/failed` (no completion arrives). We cannot and do not try to prevent force-stop.
7. Safety: the service stops ringing automatically at the deadline (`T0 + 30 min`) to avoid ringing forever.

### 6.4 `AlarmScheduler` (Android) contract
Same shape as iOS: `authorizationState()`, `sync(schedules, now)`, `onRingStarted(occurrenceId)`, `onCompleted(occurrenceId)`, `reconcile(now)`.

## 7. Wake attempt lifecycle (shared)

```
scheduled ──► ringing ──► in_progress ──► succeeded
    │            │              └────────► failed (gave up / window expired / deadline)
    │            └──► missed (no camera session before deadline)
    ├──► skipped (user skipped ≥ 15 min before T0)
    ├──► paused
    └──► void (proven system failure, see §8)
```
- The client computes a provisional state; the server decides the final one from the signed rep log + schedule snapshot (doc 06, doc 12 `submit-rep-session`).
- **Schedule snapshot:** the server takes the challenge occurrence for each user/date from `alarm_schedules` as it was **15 min before T0** (`alarm_schedule_versions` history). Edits within 15 min of T0 don't affect that occurrence (PS-26).
- Streak: consecutive local days with `succeeded`. `skipped`, `paused` (within monthly limit) and `void` **freeze** the streak (no +1, no reset). `failed`/`missed` reset it unless a **streak freeze** item is available (earned via achievements or Pro, max 2 stored), which is auto-consumed.

## 8. Alarm health check

A pure function `alarmHealth(state) -> [HealthIssue]` evaluated on app start, foreground, and before each night (local notification at 21:00 if any **critical** issue exists and an alarm is scheduled within 24 h).

| Issue | Platform | Severity | Fix action |
|---|---|---|---|
| AlarmKit not authorised | iOS | critical | open Settings |
| Exact alarm permission missing | Android | critical | `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` |
| Full-screen intent not allowed | Android 14+ | critical | `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` |
| Notifications blocked | Android | critical | app notification settings |
| Alarm channel muted / importance lowered | Android | critical | channel settings |
| Battery optimisation restricted on aggressive OEM | Android | warning | battery settings + guide |
| Camera permission denied | both | critical (can't complete challenge) | Settings |
| Scheduled window empty / next alarm not armed | both | critical | auto-repair, then show if still failing |
| Alarm volume at 0 | Android | warning | open sound settings |
| Custom sound file missing | both | warning | falls back to default sound automatically |

**Void rule:** if the client can prove the alarm could not ring because of a platform failure we didn't cause (e.g. device rebooted and was never unlocked — Android direct boot not yet run), the attempt can be marked `void` by the server using the client's diagnostic report. Permission revoked by the user is **not** void (user's responsibility, but we warned them).

## 9. "Test my alarm"
Schedules a one-shot practice alarm at `now + 10 s` with the current alarm's settings, flagged `practice=true`. Full flow, no stats, no streak.

## 10. Acceptance tests (must exist before Phase 2 is done)
- AT-ALM-01: Weekly alarm with 7 different times rings at each time for 7 consecutive simulated days (time-travel test harness with injected clock on Android instrumented tests; on iOS a manual QA script + unit tests of the scheduler diff).
- AT-ALM-02: Alarm rings in Silent mode + Focus (iOS) / DND + silent (Android).
- AT-ALM-03: Alarm rings after reboot without unlocking (Android, direct boot) and after reboot (iOS).
- AT-ALM-04: Alarm rings after app force-close (swipe away) on both platforms.
- AT-ALM-05: ringUntilDone: pressing Stop (iOS) re-rings within ≤ 2 min until reps are done; Android has no stop.
- AT-ALM-06: Completing reps stops all sound within 300 ms and cancels all nags.
- AT-ALM-07: DST test vectors pass on both platforms.
- AT-ALM-08: Editing target 15 min before T0 does not change the counted occurrence (server test).
- AT-ALM-09: Revoking each permission shows the right health banner within 1 s of returning to the app.
- AT-ALM-10: 30 consecutive real nights on the QA device pool with 0 missed rings (release gate — doc 18).
