# 11 — Data model (Supabase Postgres)

Conventions: CLAUDE.md §6. All tables in schema `public` unless noted; private helper functions in schema `app`. Every table: **RLS enabled**. Competitive tables: **no client writes** (only `SECURITY DEFINER` functions / Edge Functions with the service role).

Split this into migrations in order: `0001_extensions_enums`, `0002_profiles_devices`, `0003_social`, `0004_alarms_wake`, `0005_sessions_stats`, `0006_battles_ranking`, `0007_clans`, `0008_progress_items`, `0009_monetization`, `0010_moderation_config`, `0011_rls_policies`, `0012_functions`, `0013_cron`.

## 1. Extensions & enums
```sql
create extension if not exists citext;
create extension if not exists pg_cron;
create extension if not exists pgcrypto;

create type platform_t        as enum ('ios','android');
create type visibility_t      as enum ('public','friends','private');
create type friendship_status as enum ('pending','accepted','blocked');
create type session_context   as enum ('wake','battle','training');
create type wake_status       as enum ('scheduled','ringing','in_progress','succeeded','failed','missed','skipped','paused','void');
create type battle_type       as enum ('quick','friend_ranked','friendly','ghost');
create type battle_mode       as enum ('max_reps','best_of_3','speed','turns','endurance');
create type battle_status     as enum ('created','lobby','ready_check','countdown','live','round_rest','finished','settled','cancelled','void');
create type clan_role         as enum ('leader','co_leader','elder','member');
create type join_policy       as enum ('open','request','invite_only');
create type war_status        as enum ('scheduled','live','finished');
create type flag_severity     as enum ('soft','hard');
create type flag_status       as enum ('open','cleared','actioned');
```

## 2. Users & devices
```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username citext unique not null check (username ~ '^[A-Za-z0-9_.]{3,20}$'),
  avatar_preset text, avatar_path text,
  country char(2), birth_year smallint check (birth_year between 1900 and 2100),
  timezone text not null default 'UTC',
  profile_visibility visibility_t not null default 'public',
  leaderboard_visible boolean not null default true,
  trophies int not null default 0 check (trophies >= 0),
  trophy_floor int not null default 0,
  placement_battles_left smallint not null default 5,
  mmr double precision not null default 1500, mmr_rd double precision not null default 350, mmr_vol double precision not null default 0.06,
  trust_score smallint not null default 70 check (trust_score between 0 and 100),
  xp int not null default 0, level smallint not null default 1,
  is_pro boolean not null default false,          -- denormalised from entitlements by webhook
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform platform_t not null,
  model text, os_version text, app_version text,
  attest_key_id text, public_key text,           -- App Attest key id / Android Keystore public key (PEM)
  attested_at timestamptz,
  push_token text, push_token_updated_at timestamptz,
  last_seen_at timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index on devices(user_id);
```

## 3. Social
```sql
create table friendships (
  user_a uuid not null references profiles(id) on delete cascade,
  user_b uuid not null references profiles(id) on delete cascade,
  status friendship_status not null,
  requested_by uuid not null references profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index on friendships(user_b);
-- helper: app.are_friends(a uuid, b uuid) returns boolean (SECURITY DEFINER, STABLE)
```

## 4. Alarms & wake
```sql
create table alarm_schedules (
  id uuid primary key,                            -- generated on device
  user_id uuid not null references profiles(id) on delete cascade,
  version int not null,
  enabled boolean not null,
  counts_for_challenge boolean not null,
  data jsonb not null,                            -- full AlarmSchedule (shared/contracts/alarm-schedule.schema.json)
  deleted_at timestamptz,
  updated_at timestamptz not null default now()
);
create table alarm_schedule_versions (            -- history for the 15-min snapshot rule (doc 04 §7)
  alarm_id uuid not null references alarm_schedules(id) on delete cascade,
  version int not null,
  data jsonb not null,
  valid_from timestamptz not null default now(),
  primary key (alarm_id, version)
);

create table wake_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  local_date date not null,
  occurrence_id text not null,
  alarm_id uuid references alarm_schedules(id) on delete set null,
  alarm_version int not null,
  scheduled_at timestamptz not null, deadline_at timestamptz not null,
  mode jsonb not null,                            -- snapshot of the mode config
  status wake_status not null,
  session_id uuid,                                -- references rep_sessions(id), set when succeeded/failed
  final_target_reps smallint, snoozes_used smallint default 0,
  points smallint not null default 0,
  decided_at timestamptz,
  unique (user_id, local_date)
);

create table streaks (
  user_id uuid primary key references profiles(id) on delete cascade,
  current int not null default 0, best int not null default 0,          -- personal streak (freezes allowed)
  pure_current int not null default 0, pure_best int not null default 0, -- leaderboard streak (no freezes, doc 08 §3)
  last_counted_date date,
  freezes_available smallint not null default 0 check (freezes_available between 0 and 2),
  paused_days_this_month smallint not null default 0, paused_month date
);
```

## 5. Sessions & stats
```sql
create table rep_sessions (
  id uuid primary key,                            -- sessionId from the client
  user_id uuid not null references profiles(id) on delete cascade,
  device_id uuid not null references devices(id),
  context session_context not null,
  occurrence_id text, battle_id uuid, round_index smallint,
  started_at timestamptz not null, ended_at timestamptz not null,
  reps_counted int not null check (reps_counted >= 0),
  best_set int not null default 0,
  avg_quality smallint, avg_depth real, avg_body_line real, avg_tempo_ms int,
  spec_version smallint not null, app_version text not null,
  verified boolean not null default false,
  verification jsonb not null default '{}',       -- per-check results, suspicion scores
  late boolean not null default false,
  received_at timestamptz not null default now()
);
create index on rep_sessions(user_id, started_at desc);
create index on rep_sessions(battle_id);

create table rep_session_logs (                   -- raw signed logs, retention 90 days (cron purge)
  session_id uuid primary key references rep_sessions(id) on delete cascade,
  log jsonb not null, signature text not null,
  created_at timestamptz not null default now()
);

-- Competitive aggregates (UTC periods)
create table user_stats_daily (
  user_id uuid not null references profiles(id) on delete cascade,
  day date not null,                              -- UTC day
  reps_total int not null default 0, reps_wake int not null default 0,
  reps_battle int not null default 0, reps_training int not null default 0,
  wake_points int not null default 0, sessions int not null default 0,
  primary key (user_id, day)
);
create table user_stats_weekly  (user_id uuid, week_start date, reps_total int default 0, wake_points int default 0, primary key (user_id, week_start));
create table user_stats_monthly (user_id uuid, month date,      reps_total int default 0, wake_points int default 0, primary key (user_id, month));
create table user_stats_alltime (user_id uuid primary key, reps_total bigint default 0, wake_points bigint default 0, best_set int default 0);
create index on user_stats_daily  (day, reps_total desc);
create index on user_stats_weekly (week_start, reps_total desc);
create index on user_stats_weekly (week_start, wake_points desc);
create index on user_stats_monthly(month, reps_total desc);
create index on user_stats_monthly(month, wake_points desc);
create index on user_stats_alltime(reps_total desc);

-- Personal aggregates (user's local day)
create table user_stats_local_daily (
  user_id uuid not null references profiles(id) on delete cascade,
  local_date date not null,
  reps_total int default 0, reps_wake int default 0, reps_battle int default 0, reps_training int default 0,
  best_set int default 0, avg_quality smallint, sessions int default 0,
  primary key (user_id, local_date)
);

create table personal_records (
  user_id uuid not null references profiles(id) on delete cascade,
  record text not null,                           -- 'best_set','max_60s','fastest_20_ms','max_day',...
  value int not null, session_id uuid, achieved_at timestamptz not null,
  primary key (user_id, record)
);
```

## 6. Battles & ranking
```sql
create table seasons (id smallint primary key, starts_at timestamptz not null, ends_at timestamptz not null, status text not null);

create table battles (
  id uuid primary key default gen_random_uuid(),
  type battle_type not null, mode battle_mode not null,
  variant jsonb not null default '{}',            -- e.g. {"durationS":60} or {"targetReps":20}
  ranked boolean not null,
  player_a uuid references profiles(id) on delete set null,   -- null after account deletion → UI shows "Deleted user"
  player_b uuid references profiles(id) on delete set null,   -- null for ghost battles or deleted account
  player_a_name text not null, player_b_name text,           -- username snapshot at battle time
  ghost_run_id uuid,
  status battle_status not null default 'created',
  start_at timestamptz, ended_at timestamptz, settled_at timestamptz,
  result jsonb,                                   -- {"a":{"reps":..,"rounds":..},"b":{..},"reason":"..."}
  winner uuid,
  season_id smallint references seasons(id),
  livekit_room text,
  created_at timestamptz not null default now(),
  check (player_a <> player_b)
);
create index on battles(player_a, created_at desc);
create index on battles(player_b, created_at desc);

create table battle_events (
  id bigint generated always as identity primary key,
  battle_id uuid not null references battles(id) on delete cascade,
  user_id uuid not null, round_index smallint not null default 0,
  rep_index int not null, t_end_server_ms bigint not null, quality smallint,
  received_at timestamptz not null default now(),
  unique (battle_id, user_id, round_index, rep_index)
);

create table battle_invites (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references profiles(id), to_user uuid references profiles(id),
  code text unique,                               -- share-link code
  mode battle_mode not null, variant jsonb not null default '{}', ranked boolean not null default false,
  status text not null default 'pending',         -- pending/accepted/declined/expired
  battle_id uuid references battles(id),
  expires_at timestamptz not null, created_at timestamptz not null default now()
);

create table matchmaking_queue (
  user_id uuid primary key references profiles(id) on delete cascade,
  mode battle_mode not null, variant jsonb not null default '{}',
  mmr double precision not null, trust_bucket smallint not null, region text not null,
  last_opponent uuid, joined_at timestamptz not null default now()
);

create table trophy_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  battle_id uuid references battles(id),
  delta int not null, balance_after int not null,
  reason text not null,                           -- 'battle_win','battle_loss','placement','streak_bonus','reversal','season_reset'
  season_id smallint references seasons(id),
  created_at timestamptz not null default now()
);
create index on trophy_ledger(user_id, created_at desc);

create table season_results (season_id smallint, user_id uuid, best_league text, final_trophies int, final_rank int, primary key (season_id, user_id));

create table ghost_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  mode battle_mode not null, variant jsonb not null,
  mmr_at double precision not null,
  timeline jsonb not null,                        -- [{tEndMs, quality}]
  source_session uuid references rep_sessions(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table leaderboard_snapshots (
  board text not null, scope text not null, scope_key text not null default '',   -- scope: global/country; key: 'CZ'
  period_key text not null,                       -- '2026-W43', '2026-10', 'all', 'season-12', '2026-10-20'
  rank int not null, user_id uuid, clan_id uuid, score bigint not null,
  refreshed_at timestamptz not null default now(),
  primary key (board, scope, scope_key, period_key, rank)
);
```

## 7. Clans
```sql
create table clans (
  id uuid primary key default gen_random_uuid(),
  name citext unique not null, tag citext unique not null check (tag ~ '^[A-Z0-9]{3,5}$'),
  badge jsonb not null, description text check (char_length(description) <= 200),
  join_policy join_policy not null default 'open',
  min_trophies int not null default 0, country char(2),
  war_enabled boolean not null default true,
  rating int not null default 1000, member_count smallint not null default 0,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table clan_members (
  clan_id uuid not null references clans(id) on delete cascade,
  user_id uuid not null unique references profiles(id) on delete cascade,   -- one clan per user
  role clan_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (clan_id, user_id)
);
create table clan_join_requests (clan_id uuid references clans(id) on delete cascade, user_id uuid references profiles(id) on delete cascade,
  message text, status text not null default 'pending', created_at timestamptz default now(), primary key (clan_id, user_id));
create table clan_messages (
  id bigint generated always as identity primary key,
  clan_id uuid not null references clans(id) on delete cascade,
  user_id uuid references profiles(id) on delete set null,     -- null = system message
  kind text not null default 'text',                           -- text/system/kudos
  body text check (char_length(body) <= 500), meta jsonb,
  deleted_at timestamptz, created_at timestamptz not null default now()
);
create index on clan_messages(clan_id, created_at desc);
create table clan_events (id bigint generated always as identity primary key, clan_id uuid, actor uuid, type text, payload jsonb, created_at timestamptz default now());

create table clan_wars (
  id uuid primary key default gen_random_uuid(),
  week_start date not null,                       -- Monday (UTC)
  clan_a uuid not null references clans(id), clan_b uuid references clans(id),  -- b null = bye
  status war_status not null default 'scheduled',
  score_a bigint not null default 0, score_b bigint not null default 0,
  winner uuid, finished_at timestamptz,
  unique (week_start, clan_a)
);
create table clan_war_rosters (war_id uuid references clan_wars(id) on delete cascade, clan_id uuid, user_id uuid, left_at timestamptz,
  primary key (war_id, user_id));
create table clan_war_member_daily (
  war_id uuid not null references clan_wars(id) on delete cascade,
  user_id uuid not null, day date not null,       -- UTC
  raw_reps int not null default 0, counted_reps int not null default 0,
  primary key (war_id, user_id, day)
);
```

## 8. Progress, items, monetization, moderation, config
```sql
create table achievement_definitions (id text primary key, title text, description text, icon text, tier smallint, rule jsonb not null, xp int not null default 0, active boolean default true);
create table user_achievements (user_id uuid references profiles(id) on delete cascade, achievement_id text references achievement_definitions(id), unlocked_at timestamptz default now(), primary key (user_id, achievement_id));

create table items (id text primary key, kind text not null, -- frame/badge/emote/theme/sound/streak_freeze
  title text, asset jsonb, pro_only boolean default false);
create table inventory (user_id uuid references profiles(id) on delete cascade, item_id text references items(id), source text, quantity int default 1, acquired_at timestamptz default now(), equipped boolean default false, primary key (user_id, item_id));

create table entitlements (
  user_id uuid primary key references profiles(id) on delete cascade,
  pro_active boolean not null default false, product_id text, store text, expires_at timestamptz,
  rc_app_user_id text, updated_at timestamptz not null default now()
);

create table anti_cheat_flags (id bigint generated always as identity primary key, user_id uuid not null, session_id uuid, battle_id uuid,
  type text not null, severity flag_severity not null, details jsonb, status flag_status not null default 'open',
  trust_delta smallint not null default 0, created_at timestamptz default now(), resolved_by uuid, resolved_at timestamptz);
create table reports (id bigint generated always as identity primary key, reporter uuid not null, target_user uuid, battle_id uuid, message_id bigint,
  reason text not null, details text, status text default 'open', created_at timestamptz default now());
create table review_clips (id uuid primary key default gen_random_uuid(), user_id uuid not null, session_id uuid not null, storage_path text not null,
  expires_at timestamptz not null, created_at timestamptz default now());

create table notification_prefs (user_id uuid primary key references profiles(id) on delete cascade, prefs jsonb not null default '{}');
create table push_outbox (id bigint generated always as identity primary key, user_id uuid not null references profiles(id) on delete cascade,
  type text not null, payload jsonb not null, collapse_key text, silent boolean not null default false,
  send_after timestamptz not null default now(), sent_at timestamptz, attempts smallint not null default 0, last_error text);
create index on push_outbox(sent_at, send_after);
create table rate_limits (user_id uuid not null, key text not null, window_start timestamptz not null, count int not null default 0,
  primary key (user_id, key, window_start));
create table app_config (key text primary key, value jsonb not null, min_app_version text, updated_at timestamptz default now());
create table audit_log (id bigint generated always as identity primary key, actor text, action text, subject jsonb, created_at timestamptz default now());
```

## 9. RLS policy matrix
`own` = `user_id = auth.uid()`. "fn" = only via SECURITY DEFINER function / Edge Function (service role). ✗ = denied.

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| profiles | public profiles: limited columns via view `public_profiles`; own: all | via trigger on auth signup | own, **only** columns: username, avatar_*, country, timezone, visibility, leaderboard_visible (enforced by column privileges / RPC `update_profile`) | ✗ (account deletion via fn) |
| devices | own | fn | fn | fn |
| friendships | rows where caller is a or b | fn (`send_friend_request`) | fn | fn |
| alarm_schedules / versions | own | own (through RPC `upsert_alarm` which writes version history) | RPC | RPC (soft delete) |
| wake_attempts, streaks | own (+ friends: streak current/best only via view) | fn | fn | ✗ |
| rep_sessions | own; friends see aggregates only via views | fn | fn | ✗ |
| rep_session_logs | ✗ (service only) | fn | ✗ | cron |
| user_stats_* | own; others via leaderboard RPCs/views | fn | fn | ✗ |
| battles | participants | fn | fn | ✗ |
| battle_events | participants | RPC `battle_push_rep` (checks participant + status live) | ✗ | ✗ |
| battle_invites | from/to user | RPC | RPC | ✗ |
| matchmaking_queue | own | fn | fn | own (leave queue) via RPC |
| trophy_ledger | own | fn | ✗ | ✗ |
| leaderboard_snapshots | everyone (authenticated) | cron | cron | cron |
| clans | everyone (authenticated) | RPC `create_clan` | RPC (role check) | RPC (leader) |
| clan_members | everyone (authenticated) | RPC | RPC | RPC |
| clan_messages | members of that clan | RPC `send_clan_message` (rate limit, filter) | RPC (delete by mod) | ✗ |
| clan_wars, rosters, member_daily | everyone (authenticated) | cron/fn | fn | ✗ |
| achievements, items | everyone | admin | admin | admin |
| user_achievements, inventory | own (+ public view of equipped cosmetics) | fn | own `equipped` via RPC | ✗ |
| entitlements | own | webhook fn | webhook fn | ✗ |
| anti_cheat_flags, review_clips, audit_log | ✗ (moderators via service role) | fn | fn | cron |
| push_outbox, rate_limits, notification_prefs | push_outbox/rate_limits ✗; notification_prefs own | fn | notification_prefs own; others fn | cron |
| reports | own (inserted) | RPC | ✗ | ✗ |
| app_config | everyone (incl. anon) | admin | admin | admin |

pgTAP tests (`supabase/tests/`) must cover, for **every** table: anon has no access (except `app_config`), user A cannot read B's private rows, user cannot write competitive tables directly, column-restricted profile updates.

## 10. Storage buckets
| Bucket | Access | Content |
|---|---|---|
| `avatars` | public read, owner write (path `{uid}/avatar.jpg`, ≤ 1 MB, image types only) | profile photos |
| `review-clips` | private, service role only; lifecycle delete after 30 days | anti-cheat clips (doc 06 §6) |
| `share-cards` | none — share cards are generated locally and not uploaded | — |

## 11. Retention
- `rep_session_logs` 90 days; `review_clips` 30 days; `clan_messages` 90 days; `battle_events` 30 days (results stay in `battles`); `matchmaking_queue` rows older than 5 min purged every minute.
- Account deletion: hard-delete the auth user, profile and all personal data within 30 days (FK cascades). In `battles` the deleted player's id becomes `null` (`on delete set null`) and the name snapshot is overwritten with `"Deleted user"`, so opponents' history and their trophy ledgers stay consistent.
