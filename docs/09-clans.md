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

## 3. Clan Wars (weekly) — v2 since D-078
- **Groups of 2–4 clans** fight each week (no more duels / byes). Migration 0034, reference
  `tools/reference/pushly_ref/clan_war_groups.py`, vectors `shared/test-vectors/clan-war/groups.json` (pgTAP 104, 105).
- **Timeline (UTC):** war **Monday 00:00 → Sunday 20:00**. Sunday 20:00 = results, then every clan goes straight into the
  lobby for next Monday. (Competitive weeks elsewhere stay Monday → Monday; the 4 h on Sunday evening are the results
  break.) `pg_cron` runs `app.clan_war_tick()` every 5 minutes: finish due wars → regroup → start due lobbies → place
  newcomers.
- **Lobby:** a clan with war on and ≥ 1 member always has one active entry (lobby or live). A new clan (or war switched
  on) is placed at once: into an open lobby for next Monday with < 4 clans and the closest average clan trophies, else a
  new lobby. So two clans created on Thursday see each other in the lobby immediately; the war still starts Monday.
- **Sunday regroup:** all clans whose war just ended + clans waiting alone, sorted by clan trophies, cut into groups as
  even as possible (≤ 4, never 1 when ≥ 2 clans: 5 → 3 + 2, 9 → 3 + 3 + 3). Lobbies that already have ≥ 2 clans stay.
- **Monday start:** lobbies with ≥ 2 clans go live. A clan still alone joins a group of 2–3, or takes one clan from a
  group of 4 (→ 3 + 2), or pairs with another lone clan; with nobody at all it **moves to next week** (chat line, lobby
  shows "Looking for opponents…").
- **Score** = counted war reps of the clan's members during the war (any context), with the anti-farming caps below.
  Points belong to the clan the member was in when the reps were done (leaving keeps them with the old clan).
- **Anti-farming caps** (per member, per UTC day): first **200** verified reps count 100 %, reps 201–400 count 50 %
  (rounded down), beyond 400 count 0. Trust 30–49 counts ×0.5, < 30 counts 0 (doc 06). `app.clan_war_day_total`.
- **Ranking:** higher score; tie → more members with ≥ 50 counted reps; tie → reached the score earlier; still tied →
  same place.
- **Clan trophies** (`clans.rating`, start 1000): pairwise Elo — each other clan in the group is one game (better place
  = 1, same = 0.5, worse = 0), **K = 30 per opponent**, Δ = round(Σ K·(S − E)). Stakes grow with the group:
  equal clans ±15 in a duel, **+45 / +15 / −15 / −45** in a group of four. Never below 0. Lobby and live screens show
  the stakes ("+26 / −34 🏆": finishing 1st / last).
- **Results:** ranks, Δ, MVP per clan, chat line + push (`clan_war_result`); the apps show a full-screen result once
  per war (stored on the device), then the next lobby. History: `get_clan_war_results`.
- War Chests are gone (D-075); the v1 tables (`clan_wars`, rosters, member_daily) stay as read-only history.
- **Who pushed (D-079):** `get_clan_war_detail(war_id)` (migration 0035, pgTAP 106, clan-war-detail.schema.json) — the
  war plus every clan's fighters: counted points, raw push-ups, points per war day (Mon..Sun) and whether they are still
  in the clan. Members who were in the clan before the war ended but scored nothing are listed with **0** ("Didn't
  fight") so leaders can see who pulls their weight; anyone in the war can look at every clan. `get_clan_war_results`
  also returns the clan's `mvp` and `contributors`.

## 4. Clan home UI
> **D-079 — live arena + pages:** the lobby card has no LOBBY tag any more (neutral frame; LIVE stays red). A live war
> of 3–4 clans is a **race**: one lane per clan, the clan badge runs toward the leader's mark, the score rolls up,
> "+N" pops over the clan that just scored, lanes swap when a clan overtakes and the leader wears 👑; duels keep the
> face-off with an animated tug bar. Under it a ticker with the newest feed line. The tab refreshes the war every
> 15 s while it is live (Reduce Motion: no movement). **War history** looks like Battle history: a record card (wars
> won ring, wins / wars, last 10 places, clan trophies ±, best streak) and a card per war (VICTORY / 2ND / LAST,
> every clan with score bars, Δ, MVP, fighters) → **Who pushed** (clan picker, idle warning, each fighter with 7 day
> bars). Tapping a clan anywhere in the war (standings, results, who pushed) or your own clan's name opens the
> **clan page**: badge, description, clan trophies, members, wars won, join policy, current war, members with role,
> trophies and this war's points.
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
