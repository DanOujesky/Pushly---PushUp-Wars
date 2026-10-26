# 09 — Clans & Clan Wars

## 1. Clan basics
| Field | Rules |
|---|---|
| name | 3–24 chars, unique (case-insensitive), profanity-filtered |
| tag | 3–5 chars `[A-Z0-9]`, unique, shown as `[TAG]` next to usernames |
| badge | preset shape + color + emblem (Pro: extra emblems — cosmetic only) |
| description | ≤ 200 chars |
| join policy | `open` / `request` / `invite_only` |
| requirements | min trophies (optional), country (optional) |
| size | max **30** members; creating a clan is free |

One clan per user. Leaving a clan: 24 h cooldown before joining another clan's **war roster** (you can join immediately, but your reps don't count for a war started before you joined anyway — §3).

## 2. Roles & permissions
| Action | Leader (1) | Co-leader (≤ 3) | Elder | Member |
|---|---|---|---|---|
| Edit clan settings | ✅ | ✅ | ❌ | ❌ |
| Accept requests / invite | ✅ | ✅ | ✅ | ❌ |
| Kick | ✅ any | Elders & Members | Members | ❌ |
| Promote / demote | ✅ | up to Elder | ❌ | ❌ |
| Toggle war participation | ✅ | ✅ | ❌ | ❌ |
| Delete chat messages | ✅ | ✅ | ❌ | ❌ |
| Transfer leadership / disband | ✅ | ❌ | ❌ | ❌ |
- Leader inactive 14 days → leadership auto-transfers to the most active co-leader (then elder, then member) by last-14-day verified reps.
- All role changes go through RPCs that check the caller's role (never trust client), logged in `clan_events`.

## 3. Clan Wars (weekly)
- **War week:** Monday 00:00 UTC → next Monday 00:00 UTC.
- **Participation:** clans with ≥ 1 member (solo is fine, D-076) and war toggle on (default on) at **Sunday 23:00 UTC** are entered.
- **Roster:** members of the clan at war start. Members joining mid-war don't contribute to that war. Members leaving mid-war: reps before leaving still count.
- **Matching** (`pg_cron` Monday 00:00 UTC, function `clan_war_matchmake()`):
  1. compute `active_members` = roster members with ≥ 1 verified session in the previous 7 days;
  2. bucket clans by `active_members` (±20 %), then pair by `clan_rating` (Elo, start 1000) closest first;
  3. avoid the same opponent as last week;
  4. an odd clan out gets a **bye** (auto-win with half rewards, no rating change).
- **Score** = sum of **counted war reps** of roster members during the week, from all contexts (wake, battles, training).
- **Anti-farming caps** (per member, per UTC day): first **200** verified reps count 100 %, reps 201–400 count 50 % (rounded down), beyond 400 count 0. Users with trust 30–49 count ×0.5 (doc 06). Implemented in SQL (`clan_war_count(reps_today_before, new_reps)` — pure function with test vectors in `shared/test-vectors/clan-war`).
- **Live ticker:** `clan_war_scores` updated in the same transaction as each validated session; Realtime broadcast on channel `clan_war:{war_id}` (throttled to 1 update / 5 s).
- **End** (`pg_cron` Monday 00:00 UTC, before matching the next war): finalize — winner = higher score; tie → more members who contributed ≥ 50 reps → earlier time the final score was reached.
- **Rewards:**
  - clan rating Elo update (K = 32);
  - every roster member with ≥ 50 counted war reps gets a **War Chest** (cosmetic only: profile frames, badges, emotes, XP). Winners get the gold chest, losers silver, bye bronze;
  - MVP badge for the top contributor of each clan.

## 4. Clan home UI
> **Built as a game lobby (D-074):** one static screen, no scrolling — top bar (badge, name, role, rating, settings),
> the war arena (both badges, scores, tug-of-war bar, time left, days won; tap → war details), your push-ups today
> with the caps, **PUSH FOR [TAG]** (free training), and tiles Members / Chat / Chests / Wars (sheets). Without a
> clan: "Join a clan" with FIND A CLAN + Create. Badge = shape + colour + emblem (shared/cosmetics/cosmetics.json),
> edited by leaders / co-leaders; 8 of the 16 emblems need Pushly Pro.
> **D-075:** creating a clan needs only a name and a description — the server picks the (internal) tag from the name;
> the apps show names, not tags. **No War Chests** anymore (the grant trigger is dropped; the tiles are Members, Chat,
> Wars).

- Header: badge, name, tag, rating, members x/30, country.
- **War card:** opponent badge/name, live scores with animated bars, time left, your contribution today ("+120 today (cap 200)"), "Do push-ups" CTA.
- Members list: avatar, name, role, trophies, today's reps, this week's war reps, last active. Sort by war reps.
- Clan stats: weekly reps chart (stacked by member), war history (W/L streak).
- Chat (§5).
- Discovery (when not in a clan): search by name/tag, filters (open, country, min trophies, size), recommended clans (similar trophies, same country, has space).

## 5. Clan chat (v1 — only chat in the app)
- Messages: text ≤ 500 chars, system messages (joined/left/promoted, war started/ended, "Dan did 50 push-ups ⚡"), push-up "kudos" reactions (👊 🔥 💪 only — fixed set).
- Transport: Supabase Realtime (postgres changes on `clan_messages` filtered by `clan_id`, RLS ensures members only).
- Rate limit: 1 message / 2 s, 200 / day per user (RPC enforces).
- Profanity filter server-side (masking), report message, leaders/co-leaders delete. Retention: 90 days.
- Users can mute clan chat notifications.
