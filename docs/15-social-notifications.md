# 15 — Social & notifications

## 1. Friends
- Add by username search, by share link `https://pushly.app/u/{username}` (Universal/App Links), or QR code. The same three ways appear in Battle → Friends, on the Profile tab Friends card (Find / Share link / QR code) and in the **Add** tab of Profile → Friends (Activity · Friends · Add), D-077.
- Optional contacts matching is **not** in v1 (privacy).
- Request → accept/decline; max 500 friends; block hides both users from each other everywhere (search, leaderboards friends scope, invites).
- Friends see: profile (per visibility), streak, league, clan, today's reps, recent achievements, battle record vs. them.
- **Friends activity feed** (Profile → Friends, simple list, not a social network): "Ana beat her wake challenge (30 reps) · 6:12", "Tom reached Gold II". Generated from events; last 7 days.
- **Kudos:** one tap 👊 on a feed item (max 1 per item), notifies the friend (batched).

## 2. Notification types
Delivered via `push_outbox` (doc 12). Users control categories in Settings. Quiet hours: default 22:00–07:00 local (except alarm-related and battle invites the user explicitly started).

| Type | Default | Category | Notes |
|---|---|---|---|
| Bedtime reminder | off | Alarm | local notification (scheduled on device) |
| Pre-alarm heads-up | off | Alarm | local |
| Alarm health critical (evening check) | **on** | Alarm | local, 21:00 (doc 04 §8) |
| Alarms running out | **on** | Alarm | server push (doc 04 §5.3) |
| Wake result validated (if app closed before validation) | on | Activity | |
| Friend request / accepted | on | Social | |
| Battle invite | on | Battles | time-sensitive (iOS interruption level `timeSensitive`) |
| Your turn / rematch request | on | Battles | |
| Clan: war started / ending in 3 h / result | on | Clan | |
| Clan: join request (leaders) | on | Clan | |
| Clan chat mentions `@username` | on | Clan | regular chat messages: off by default |
| Achievement unlocked (when not in app) | on | Activity | |
| Friend overtook you on friends leaderboard (max 1/day) | on | Social | |
| Streak at risk (no challenge alarm set for tomorrow, 20:00) | on | Activity | max 3/week |
| Season ending in 24 h | on | Battles | |
| Marketing / Pro offers | **off** (opt-in) | Promotions | GDPR consent |

Caps: max 5 non-critical pushes per user per day; collapse duplicates by `collapse_key`.

## 3. Deep links (`pushly://` + Universal/App Links on `pushly.app`)
`/wake`, `/alarm/{id}`, `/battle/invite/{code}`, `/battle/{id}`, `/clan/{id}`, `/clan/war/{id}`, `/u/{username}`, `/leaderboard/{board}`, `/settings/alarm-health`, `/pro`.
