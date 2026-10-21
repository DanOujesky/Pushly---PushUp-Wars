-- 0011 — friends, activity feed + kudos (doc 15 §1), leaderboards (doc 08 §4), roadmap P6-01 / P6-03.
-- Clients never write these tables; every change is an RPC that checks the caller (CLAUDE.md §4.2).

-- ---------------------------------------------------------------------------
-- Rate limits (doc 11 §10): fixed windows per user + key.
-- ---------------------------------------------------------------------------
create table public.rate_limits (
  user_id uuid not null references public.profiles(id) on delete cascade,
  key text not null,
  window_start timestamptz not null,
  count int not null default 0,
  primary key (user_id, key, window_start)
);
alter table public.rate_limits enable row level security;
revoke all on public.rate_limits from anon, authenticated;

-- Counts one use; raises 'rate limited' (P0001 / hint rate_limited) when the window is full.
create or replace function app.hit_rate_limit(uid uuid, p_key text, p_max int, p_window interval) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  v_start timestamptz := to_timestamp(floor(extract(epoch from now()) / extract(epoch from p_window))
                                      * extract(epoch from p_window));
  v_count int;
begin
  insert into public.rate_limits as r (user_id, key, window_start, count) values (uid, p_key, v_start, 1)
  on conflict (user_id, key, window_start) do update set count = r.count + 1
  returning count into v_count;
  if v_count > p_max then
    raise exception 'rate limited' using errcode = 'P0001', hint = 'rate_limited';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Friendships (doc 11 §3): one row per pair, user_a < user_b.
-- ---------------------------------------------------------------------------
create table public.friendships (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  status public.friendship_status not null,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  blocked_by uuid references public.profiles(id) on delete cascade,   -- set when status = blocked
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b),
  check ((status = 'blocked') = (blocked_by is not null))
);
create index friendships_user_b_idx on public.friendships(user_b);
create trigger friendships_touch before update on public.friendships
  for each row execute function app.touch_updated_at();

alter table public.friendships enable row level security;
revoke insert, update, delete, truncate on public.friendships from anon, authenticated;
revoke all on public.friendships from anon;
-- Both sides see pending / accepted rows; only the blocker sees a block (the blocked user must not learn about it).
create policy friendships_select_own on public.friendships for select to authenticated
  using ((status <> 'blocked' and auth.uid() in (user_a, user_b)) or blocked_by = auth.uid());

create or replace function app.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (select 1 from public.friendships
                  where user_a = least(a, b) and user_b = greatest(a, b) and status = 'accepted')
$$;

create or replace function app.is_blocked(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (select 1 from public.friendships
                  where user_a = least(a, b) and user_b = greatest(a, b) and status = 'blocked')
$$;

create or replace function app.friend_ids(uid uuid) returns setof uuid
language sql stable security definer set search_path = public, app as $$
  select case when user_a = uid then user_b else user_a end from public.friendships
   where status = 'accepted' and uid in (user_a, user_b)
$$;

-- Card shown in friend lists, search and leaderboards (respects visibility: private profiles show name + avatar only).
create or replace function app.user_card(uid uuid, viewer uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'avatarPreset', p.avatar_preset,
    'country', p.country, 'level', p.level, 'trophies', p.trophies,
    'streak', case when p.profile_visibility = 'public' or p.id = viewer
                     or (p.profile_visibility = 'friends' and app.are_friends(p.id, viewer))
                   then coalesce((select current from public.streaks s where s.user_id = p.id), 0) end)
  from public.profiles p where p.id = uid
$$;

create or replace function app.require_user() returns uuid
language plpgsql stable as $$
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  return auth.uid();
end $$;

-- Target of a social action by id; blocked pairs and unfinished profiles look like "not found" (no block leak).
create or replace function app.social_target(me uuid, target uuid) returns uuid
language plpgsql stable security definer set search_path = public, app as $$
begin
  if target is null or target = me
     or not exists (select 1 from public.profiles where id = target and onboarding_completed)
     or exists (select 1 from public.friendships where user_a = least(me, target) and user_b = greatest(me, target)
                   and status = 'blocked' and blocked_by = target) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  return target;
end $$;

-- Send a request by user id. A pending request from the other side is accepted instead. Max 500 friends, 50 requests / day.
create or replace function public.send_friend_request(target uuid) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_row public.friendships;
  v_count int;
begin
  perform app.social_target(me, target);
  select * into v_row from public.friendships where user_a = least(me, target) and user_b = greatest(me, target) for update;
  if found then
    if v_row.status = 'accepted' then return 'friends'; end if;
    if v_row.status = 'blocked' then
      raise exception 'unblock this user first' using errcode = '22023';   -- only reachable for the blocker
    end if;
    if v_row.requested_by = me then return 'pending'; end if;
    update public.friendships set status = 'accepted' where user_a = v_row.user_a and user_b = v_row.user_b;
    perform app.enqueue_push(target, 'friend_accepted', 'social',
      jsonb_build_object('userId', me, 'username', (select username from public.profiles where id = me)), 'friend:' || me);
    return 'friends';
  end if;
  select count(*) into v_count from app.friend_ids(me);
  if v_count >= 500 then raise exception 'friend limit reached' using errcode = '22023', hint = 'friend_limit'; end if;
  perform app.hit_rate_limit(me, 'friend_request', 50, interval '1 day');
  insert into public.friendships (user_a, user_b, status, requested_by)
  values (least(me, target), greatest(me, target), 'pending', me);
  perform app.enqueue_push(target, 'friend_request', 'social',
    jsonb_build_object('userId', me, 'username', (select username from public.profiles where id = me)), 'friend:' || me);
  return 'pending';
end $$;

create or replace function public.respond_friend_request(requester uuid, accept boolean) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  if accept then
    update public.friendships set status = 'accepted'
     where user_a = least(me, requester) and user_b = greatest(me, requester) and status = 'pending' and requested_by = requester;
    if not found then raise exception 'request not found' using errcode = 'P0002'; end if;
    perform app.enqueue_push(requester, 'friend_accepted', 'social',
      jsonb_build_object('userId', me, 'username', (select username from public.profiles where id = me)), 'friend:' || me);
    return 'friends';
  end if;
  delete from public.friendships
   where user_a = least(me, requester) and user_b = greatest(me, requester) and status = 'pending' and requested_by = requester;
  return 'none';
end $$;

-- Unfriend, or cancel my own pending request.
create or replace function public.remove_friend(target uuid) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  delete from public.friendships
   where user_a = least(me, target) and user_b = greatest(me, target) and status in ('pending', 'accepted');
  return 'none';
end $$;

-- Block hides both users from each other everywhere (search, friends boards, feed, invites). Replaces any friendship.
create or replace function public.block_user(target uuid) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  if target is null or target = me or not exists (select 1 from public.profiles where id = target) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  insert into public.friendships (user_a, user_b, status, requested_by, blocked_by)
  values (least(me, target), greatest(me, target), 'blocked', me, me)
  on conflict (user_a, user_b) do update set status = 'blocked', blocked_by = me, requested_by = me
   where public.friendships.status <> 'blocked';   -- the first block stands
  return 'blocked';
end $$;

create or replace function public.unblock_user(target uuid) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  delete from public.friendships
   where user_a = least(me, target) and user_b = greatest(me, target) and status = 'blocked' and blocked_by = me;
  return 'none';
end $$;

-- Friends screen: accepted friends, incoming and outgoing requests, my blocks.
create or replace function public.list_friends() returns jsonb
language sql stable security definer set search_path = public, app as $$
  with me as (select app.require_user() as id),
  rel as (
    select case when f.user_a = me.id then f.user_b else f.user_a end as other, f.status, f.requested_by, f.blocked_by,
           f.updated_at
      from public.friendships f, me where me.id in (f.user_a, f.user_b))
  select jsonb_build_object(
    'friends', coalesce((select jsonb_agg(app.user_card(other, (select id from me)) order by lower(p.username))
                           from rel join public.profiles p on p.id = rel.other where rel.status = 'accepted'), '[]'),
    'incoming', coalesce((select jsonb_agg(app.user_card(other, (select id from me)) order by rel.updated_at desc)
                            from rel where status = 'pending' and requested_by = other), '[]'),
    'outgoing', coalesce((select jsonb_agg(app.user_card(other, (select id from me)) order by rel.updated_at desc)
                            from rel where status = 'pending' and requested_by = (select id from me)), '[]'),
    'blocked', coalesce((select jsonb_agg(jsonb_build_object('id', other, 'username', p.username) order by lower(p.username))
                           from rel join public.profiles p on p.id = rel.other
                          where rel.status = 'blocked' and rel.blocked_by = (select id from me)), '[]'))
$$;

-- Username search (prefix, case-insensitive), max 20, never shows users who blocked me or whom I blocked.
create or replace function public.search_users(q text) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_q text := lower(trim(coalesce(q, '')));
begin
  if length(v_q) < 2 then return '[]'::jsonb; end if;
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((
    select jsonb_agg(app.user_card(p.id, me) || jsonb_build_object('relation',
             coalesce((select case when f.status = 'accepted' then 'friends'
                                   when f.requested_by = me then 'outgoing' else 'incoming' end
                         from public.friendships f
                        where f.user_a = least(me, p.id) and f.user_b = greatest(me, p.id)), 'none'))
             order by length(p.username), lower(p.username))
      from (select * from public.profiles p
             where p.onboarding_completed and p.id <> me and lower(p.username::text) like v_q || '%'
               and not app.is_blocked(me, p.id)
             order by length(p.username), lower(p.username) limit 20) p), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Activity feed + kudos (doc 15 §1). Events are written by triggers on authoritative tables.
-- ---------------------------------------------------------------------------
create table public.activity_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('wake_beaten', 'achievement', 'level_up', 'best_set')),
  payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index activity_events_user_idx on public.activity_events(user_id, created_at desc);

create table public.kudos (
  event_id bigint not null references public.activity_events(id) on delete cascade,
  from_user uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (event_id, from_user)
);

alter table public.activity_events enable row level security;
alter table public.kudos enable row level security;
revoke all on public.activity_events, public.kudos from anon, authenticated;   -- read via get_friend_feed only

create or replace function app.on_wake_attempt_event() returns trigger
language plpgsql security definer set search_path = public, app as $$
begin
  if new.status = 'succeeded' and (tg_op = 'INSERT' or old.status is distinct from 'succeeded') then
    insert into public.activity_events (user_id, kind, payload)
    values (new.user_id, 'wake_beaten', jsonb_build_object('reps', new.score, 'points', new.points,
            'localDate', new.local_date, 'mode', new.mode->>'type'));
  end if;
  return new;
end $$;
create trigger wake_attempts_activity after insert or update of status on public.wake_attempts
  for each row execute function app.on_wake_attempt_event();

create or replace function app.on_achievement_event() returns trigger
language plpgsql security definer set search_path = public, app as $$
begin
  insert into public.activity_events (user_id, kind, payload)
  select new.user_id, 'achievement', jsonb_build_object('id', d.id, 'title', d.title, 'icon', d.icon, 'tier', d.tier)
    from public.achievement_definitions d where d.id = new.achievement_id;
  return new;
end $$;
create trigger user_achievements_activity after insert on public.user_achievements
  for each row execute function app.on_achievement_event();

create or replace function app.on_level_event() returns trigger
language plpgsql security definer set search_path = public, app as $$
begin
  if new.level > old.level then
    insert into public.activity_events (user_id, kind, payload) values (new.id, 'level_up', jsonb_build_object('level', new.level));
  end if;
  return new;
end $$;
create trigger profiles_level_activity after update of level on public.profiles
  for each row execute function app.on_level_event();

create or replace function app.on_record_event() returns trigger
language plpgsql security definer set search_path = public, app as $$
begin
  if new.record = 'best_set' and (tg_op = 'INSERT' or new.value > old.value) then
    insert into public.activity_events (user_id, kind, payload) values (new.user_id, 'best_set', jsonb_build_object('reps', new.value));
  end if;
  return new;
end $$;
create trigger personal_records_activity after insert or update on public.personal_records
  for each row execute function app.on_record_event();

-- Friends' events of the last 7 days (newest first, max 100) with kudos counts.
create or replace function public.get_friend_feed() returns jsonb
language sql stable security definer set search_path = public, app as $$
  with me as (select app.require_user() as id)
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'user', app.user_card(e.user_id, (select id from me)), 'kind', e.kind, 'payload', e.payload,
      'createdAt', app.utc_iso(e.created_at),
      'kudos', (select count(*) from public.kudos k where k.event_id = e.id),
      'kudosByMe', exists (select 1 from public.kudos k where k.event_id = e.id and k.from_user = (select id from me)))
    order by e.created_at desc, e.id desc), '[]')
  from (select * from public.activity_events
         where user_id in (select app.friend_ids((select id from me))) and created_at > now() - interval '7 days'
         order by created_at desc, id desc limit 100) e
$$;

-- 👊 on a friend's event (max 1 per event). Notifies the friend, collapsed per day.
create or replace function public.give_kudos(event_id bigint) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_owner uuid;
  v_count int;
begin
  select user_id into v_owner from public.activity_events e where e.id = give_kudos.event_id;
  if v_owner is null or not app.are_friends(me, v_owner) then
    raise exception 'event not found' using errcode = 'P0002';
  end if;
  insert into public.kudos (event_id, from_user) values (give_kudos.event_id, me) on conflict do nothing;
  if found then
    perform app.enqueue_push(v_owner, 'kudos', 'social',
      jsonb_build_object('userId', me, 'username', (select username from public.profiles where id = me), 'eventId', give_kudos.event_id),
      'kudos:' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'));
  end if;
  select count(*) into v_count from public.kudos k where k.event_id = give_kudos.event_id;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Push outbox (doc 12, doc 15 §2) — the sender (Edge Function push-send) comes with P6-05; enqueueing already
-- respects preferences, quiet hours and the daily cap so callers never have to.
-- ---------------------------------------------------------------------------
create table public.notification_prefs (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  prefs jsonb not null default '{}'
);
create table public.push_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  category text not null,
  payload jsonb not null,
  collapse_key text,
  silent boolean not null default false,
  send_after timestamptz not null default now(),
  sent_at timestamptz,
  attempts smallint not null default 0,
  last_error text,
  created_at timestamptz not null default now()
);
create index push_outbox_due_idx on public.push_outbox(send_after) where sent_at is null;
create unique index push_outbox_collapse_idx on public.push_outbox(user_id, collapse_key) where sent_at is null and collapse_key is not null;

alter table public.notification_prefs enable row level security;
alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from anon, authenticated;
revoke insert, update, delete, truncate on public.notification_prefs from anon, authenticated;
revoke all on public.notification_prefs from anon;
create policy notification_prefs_select_own on public.notification_prefs for select to authenticated using (user_id = auth.uid());

-- Categories (doc 15 §2) and their defaults; "alarm" is never muted by quiet hours.
create or replace function app.push_category_default(category text) returns boolean
language sql immutable as $$
  select case category when 'promotions' then false else true end
$$;

-- prefs: {"categories": {"social": false, ...}, "quietStart": "22:00", "quietEnd": "07:00"}
create or replace function app.enqueue_push(uid uuid, p_type text, p_category text, p_payload jsonb,
                                            p_collapse text default null) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  v_prefs jsonb;
  v_tz text;
  v_local time;
  v_qs time;
  v_qe time;
  v_after timestamptz := now();
  v_today int;
begin
  select coalesce(n.prefs, '{}'), coalesce(p.timezone, 'UTC') into v_prefs, v_tz
    from public.profiles p left join public.notification_prefs n on n.user_id = p.id where p.id = uid;
  if not found then return; end if;
  if not coalesce((v_prefs->'categories'->>p_category)::boolean, app.push_category_default(p_category)) then return; end if;
  if p_category <> 'alarm' then
    -- daily cap: 5 non-critical pushes per user per day (doc 15 §2)
    select count(*) into v_today from public.push_outbox
     where user_id = uid and category <> 'alarm' and created_at > now() - interval '1 day';
    if v_today >= 5 then return; end if;
    -- quiet hours (default 22:00–07:00 local): hold until they end
    v_qs := coalesce(v_prefs->>'quietStart', '22:00')::time;
    v_qe := coalesce(v_prefs->>'quietEnd', '07:00')::time;
    v_local := (now() at time zone v_tz)::time;
    if (v_qs > v_qe and (v_local >= v_qs or v_local < v_qe)) or (v_qs < v_qe and v_local >= v_qs and v_local < v_qe) then
      v_after := ((((now() at time zone v_tz)::date + case when v_local >= v_qe then 1 else 0 end) + v_qe)
                  at time zone v_tz);
    end if;
  end if;
  insert into public.push_outbox (user_id, type, category, payload, collapse_key, send_after)
  values (uid, p_type, p_category, p_payload, p_collapse, v_after)
  on conflict (user_id, collapse_key) where sent_at is null and collapse_key is not null
  do update set payload = excluded.payload, type = excluded.type;
end $$;

create or replace function public.set_notification_prefs(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  k text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'prefs must be an object' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('categories', 'quietStart', 'quietEnd') then
      raise exception 'unknown key %', k using errcode = '22023';
    end if;
  end loop;
  if p ? 'quietStart' and (p->>'quietStart') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'quietStart must be HH:MM' using errcode = '22023';
  end if;
  if p ? 'quietEnd' and (p->>'quietEnd') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'quietEnd must be HH:MM' using errcode = '22023';
  end if;
  insert into public.notification_prefs (user_id, prefs) values (me, p)
  on conflict (user_id) do update set prefs = public.notification_prefs.prefs || excluded.prefs;
  return (select prefs from public.notification_prefs where user_id = me);
end $$;

-- Push token of one of my devices (APNs / FCM). The device must be mine and not revoked.
create or replace function public.register_push_token(device_id uuid, token text) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  if token is null or length(token) not between 16 and 4096 then raise exception 'invalid token' using errcode = '22023'; end if;
  -- A token belongs to one device: drop it from any other row (reinstalls, account switches).
  update public.devices set push_token = null where push_token = token and id <> register_push_token.device_id;
  update public.devices set push_token = token, push_token_updated_at = now()
   where id = register_push_token.device_id and user_id = me and revoked_at is null;
  if not found then raise exception 'device not found' using errcode = 'P0002'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Leaderboards (doc 08 §4). Global competitive periods are UTC. Snapshots hold the top 1000 per board / scope.
-- ---------------------------------------------------------------------------
-- Verified competitive reps for the all-time board (user_stats_alltime also counts personal-only reps).
alter table public.user_stats_alltime add column reps_competitive bigint not null default 0;
update public.user_stats_alltime a set reps_competitive = coalesce((select sum(reps_total) from public.user_stats_monthly m
                                                                      where m.user_id = a.user_id), 0);
create index user_stats_alltime_competitive_idx on public.user_stats_alltime(reps_competitive desc);
create index user_stats_alltime_wake_idx on public.user_stats_alltime(wake_points desc);
create index streaks_pure_idx on public.streaks(pure_current desc, pure_best desc);

create or replace function app.bump_stats(uid uuid, at_utc timestamptz, local_d date, ctx text, p_reps int,
                                          p_best_set int, avg_q int, wake_pts int, competitive boolean)
returns void language plpgsql security definer set search_path = public, app as $$
declare
  v_day date := (at_utc at time zone 'UTC')::date;
  v_wk date := (date_trunc('week', at_utc at time zone 'UTC'))::date;
  v_mo date := (date_trunc('month', at_utc at time zone 'UTC'))::date;
begin
  if local_d is not null and ctx is not null then
    insert into public.user_stats_local_daily as l (user_id, local_date, reps_total, reps_wake, reps_battle,
      reps_training, best_set, avg_quality, sessions)
    values (uid, local_d, p_reps, case when ctx = 'wake' then p_reps else 0 end, case when ctx = 'battle' then p_reps else 0 end,
            case when ctx = 'training' then p_reps else 0 end, p_best_set, avg_q, 1)
    on conflict (user_id, local_date) do update set
      reps_total = l.reps_total + excluded.reps_total, reps_wake = l.reps_wake + excluded.reps_wake,
      reps_battle = l.reps_battle + excluded.reps_battle, reps_training = l.reps_training + excluded.reps_training,
      best_set = greatest(l.best_set, excluded.best_set),
      avg_quality = case when excluded.avg_quality is null then l.avg_quality
                         when l.avg_quality is null then excluded.avg_quality
                         else ((l.avg_quality * l.reps_total + excluded.avg_quality * excluded.reps_total)
                               / greatest(l.reps_total + excluded.reps_total, 1)) end,
      sessions = l.sessions + 1;
  end if;
  insert into public.user_stats_alltime as a (user_id, reps_total, wake_points, best_set, reps_competitive)
  values (uid, p_reps, wake_pts, p_best_set, case when competitive then p_reps else 0 end)
  on conflict (user_id) do update set reps_total = a.reps_total + excluded.reps_total,
    wake_points = a.wake_points + excluded.wake_points, best_set = greatest(a.best_set, excluded.best_set),
    reps_competitive = a.reps_competitive + excluded.reps_competitive;
  if not competitive then return; end if;
  insert into public.user_stats_daily as s (user_id, day, reps_total, reps_wake, reps_battle, reps_training,
                                            wake_points, sessions)
  values (uid, v_day, p_reps, case when ctx = 'wake' then p_reps else 0 end, case when ctx = 'battle' then p_reps else 0 end,
          case when ctx = 'training' then p_reps else 0 end, wake_pts, case when ctx is null then 0 else 1 end)
  on conflict (user_id, day) do update set reps_total = s.reps_total + excluded.reps_total,
    reps_wake = s.reps_wake + excluded.reps_wake, reps_battle = s.reps_battle + excluded.reps_battle,
    reps_training = s.reps_training + excluded.reps_training, wake_points = s.wake_points + excluded.wake_points,
    sessions = s.sessions + excluded.sessions;
  insert into public.user_stats_weekly as w (user_id, week_start, reps_total, wake_points)
  values (uid, v_wk, p_reps, wake_pts)
  on conflict (user_id, week_start) do update set reps_total = w.reps_total + excluded.reps_total,
    wake_points = w.wake_points + excluded.wake_points;
  insert into public.user_stats_monthly as m (user_id, month, reps_total, wake_points)
  values (uid, v_mo, p_reps, wake_pts)
  on conflict (user_id, month) do update set reps_total = m.reps_total + excluded.reps_total,
    wake_points = m.wake_points + excluded.wake_points;
end $$;

create table public.leaderboard_snapshots (
  board text not null,
  scope text not null,                 -- global | country
  scope_key text not null default '',  -- country code for scope = country
  period_key text not null,            -- '2026-10-21', '2026-W43', '2026-10', 'all', 'current'
  pos int not null,                    -- 1..1000 row position (ranks can tie)
  rank int not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  score bigint not null,
  refreshed_at timestamptz not null default now(),
  primary key (board, scope, scope_key, period_key, pos)
);
create index leaderboard_snapshots_user_idx on public.leaderboard_snapshots(user_id);
alter table public.leaderboard_snapshots enable row level security;
revoke all on public.leaderboard_snapshots from anon, authenticated;   -- read via get_leaderboard (names are masked there)

-- Boards and periods (doc 08 §4): wake (week, month, all), streak (current), reps (day, week, month, all).
create or replace function app.board_periods(board text) returns text[]
language sql immutable as $$
  select case board when 'wake' then array['week', 'month', 'all'] when 'streak' then array['current']
                    when 'reps' then array['day', 'week', 'month', 'all'] end
$$;

create or replace function app.period_key(period text, at_ts timestamptz default now()) returns text
language sql stable as $$
  select case period
    when 'day' then to_char(at_ts at time zone 'UTC', 'YYYY-MM-DD')
    when 'week' then to_char(at_ts at time zone 'UTC', 'IYYY-"W"IW')
    when 'month' then to_char(at_ts at time zone 'UTC', 'YYYY-MM')
    when 'all' then 'all' when 'current' then 'current' end
$$;

-- Scores of everyone on a board for the period containing at_ts. tiebreak: streak board = longer best pure streak.
create or replace function app.board_scores(board text, period text, at_ts timestamptz default now())
returns table (user_id uuid, score bigint, tiebreak bigint)
language plpgsql stable security definer set search_path = public, app as $$
declare
  v_day date := (at_ts at time zone 'UTC')::date;
  v_wk date := (date_trunc('week', at_ts at time zone 'UTC'))::date;
  v_mo date := (date_trunc('month', at_ts at time zone 'UTC'))::date;
begin
  if board = 'wake' and period = 'week' then
    return query select s.user_id, s.wake_points::bigint, 0::bigint from public.user_stats_weekly s where s.week_start = v_wk and s.wake_points > 0;
  elsif board = 'wake' and period = 'month' then
    return query select s.user_id, s.wake_points::bigint, 0::bigint from public.user_stats_monthly s where s.month = v_mo and s.wake_points > 0;
  elsif board = 'wake' and period = 'all' then
    return query select s.user_id, s.wake_points, 0::bigint from public.user_stats_alltime s where s.wake_points > 0;
  elsif board = 'streak' and period = 'current' then
    return query select s.user_id, s.pure_current::bigint, s.pure_best::bigint from public.streaks s where s.pure_current > 0;
  elsif board = 'reps' and period = 'day' then
    return query select s.user_id, s.reps_total::bigint, 0::bigint from public.user_stats_daily s where s.day = v_day and s.reps_total > 0;
  elsif board = 'reps' and period = 'week' then
    return query select s.user_id, s.reps_total::bigint, 0::bigint from public.user_stats_weekly s where s.week_start = v_wk and s.reps_total > 0;
  elsif board = 'reps' and period = 'month' then
    return query select s.user_id, s.reps_total::bigint, 0::bigint from public.user_stats_monthly s where s.month = v_mo and s.reps_total > 0;
  elsif board = 'reps' and period = 'all' then
    return query select s.user_id, s.reps_competitive, 0::bigint from public.user_stats_alltime s where s.reps_competitive > 0;
  else
    raise exception 'unknown board % / period %', board, period using errcode = '22023';
  end if;
end $$;

-- Ranked rows: competition ranking (equal score + tiebreak → same rank), only eligible users.
create or replace function app.board_ranked(board text, period text, at_ts timestamptz default now())
returns table (user_id uuid, score bigint, tiebreak bigint, rank bigint, country char(2))
language sql stable security definer set search_path = public, app as $$
  select b.user_id, b.score, b.tiebreak, rank() over (order by b.score desc, b.tiebreak desc) as rank, p.country
    from app.board_scores(board, period, at_ts) b join public.profiles p on p.id = b.user_id
   where p.onboarding_completed and p.trust_score >= 50
$$;

-- Rebuilds the snapshots for every board / period (global + per country, top 1000). Cron every 60 s (migration 0013).
create or replace function app.refresh_leaderboards(at_ts timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_board text;
  v_period text;
  v_key text;
  v_rows int := 0;
  v_n int;
begin
  for v_board in select unnest(array['wake', 'streak', 'reps']) loop
    foreach v_period in array app.board_periods(v_board) loop
      v_key := app.period_key(v_period, at_ts);
      delete from public.leaderboard_snapshots s where s.board = v_board and s.period_key = v_key;
      -- old periods of the same kind are kept 8 days for "last week" views, then dropped
      delete from public.leaderboard_snapshots s where s.board = v_board and s.refreshed_at < at_ts - interval '8 days';
      insert into public.leaderboard_snapshots (board, scope, scope_key, period_key, pos, rank, user_id, score, refreshed_at)
      select v_board, 'global', '', v_key, r.rn, r.rank, r.user_id, r.score, at_ts
        from (select x.*, row_number() over (order by x.rank, x.user_id) rn from app.board_ranked(v_board, v_period, at_ts) x) r
       where r.rn <= 1000;
      get diagnostics v_n = row_count;
      v_rows := v_rows + v_n;
      insert into public.leaderboard_snapshots (board, scope, scope_key, period_key, pos, rank, user_id, score, refreshed_at)
      select v_board, 'country', r.country, v_key, r.rn, r.crank, r.user_id, r.score, at_ts
        from (select x.*, rank() over (partition by x.country order by x.score desc, x.tiebreak desc) crank,
                     row_number() over (partition by x.country order by x.score desc, x.tiebreak desc, x.user_id) rn
                from app.board_ranked(v_board, v_period, at_ts) x where x.country is not null) r
       where r.rn <= 1000;
      get diagnostics v_n = row_count;
      v_rows := v_rows + v_n;
    end loop;
  end loop;
  return v_rows;
end $$;

-- One leaderboard row as the client shows it. Hidden users (leaderboard_visible = false) are "Anonymous athlete".
create or replace function app.board_row(p_rank bigint, uid uuid, p_score bigint, viewer uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('rank', p_rank, 'score', p_score, 'isMe', uid = viewer,
    'user', case when p.leaderboard_visible or uid = viewer then app.user_card(uid, viewer)
                 else jsonb_build_object('id', null, 'username', null, 'anonymous', true) end)
  from public.profiles p where p.id = uid
$$;

-- get_leaderboard(board, scope, period): top 100 + the caller's own row and ±10 around it (doc 08 §4, PS-60…PS-63).
-- scope: global | country (caller's country) | friends (computed live, blocked users never appear).
-- A caller who isn't eligible (trust < 50) still sees a would-be rank for themselves: "shadow" = true (doc 06).
create or replace function public.get_leaderboard(board text, scope text, period text) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_key text;
  v_country char(2);
  v_eligible boolean;
  v_me record;
  v_my_pos int;
  v_rows jsonb;
  v_around jsonb := '[]';
  v_refreshed timestamptz;
  v_scope_key text := '';
begin
  if app.board_periods(board) is null or not (period = any(app.board_periods(board))) then
    raise exception 'unknown board % / period %', board, period using errcode = '22023';
  end if;
  if scope not in ('global', 'country', 'friends') then raise exception 'unknown scope %', scope using errcode = '22023'; end if;
  v_key := app.period_key(period);
  select country, onboarding_completed and trust_score >= 50 into v_country, v_eligible from public.profiles where id = me;
  select b.score, b.tiebreak into v_me from app.board_scores(board, period) b where b.user_id = me;

  if scope = 'friends' then
    with ranked as (
      select r.user_id, r.score, rank() over (order by r.score desc, r.tiebreak desc) rk,
             row_number() over (order by r.score desc, r.tiebreak desc, r.user_id) rn
        from app.board_scores(board, period) r join public.profiles p on p.id = r.user_id
       where (r.user_id = me or r.user_id in (select app.friend_ids(me))) and p.onboarding_completed)
    select coalesce(jsonb_agg(app.board_row(rk, user_id, score, me) order by rn), '[]') into v_rows from ranked where rn <= 100;
    return jsonb_build_object('board', board, 'scope', scope, 'period', period, 'periodKey', v_key,
      'refreshedAt', app.utc_iso(now()), 'rows', v_rows, 'around', '[]'::jsonb,
      'me', case when v_me.score is null then null
                 else jsonb_build_object('score', v_me.score, 'shadow', false, 'rank',
                   1 + (select count(*) from app.board_scores(board, period) r
                         where (r.user_id in (select app.friend_ids(me)))
                           and (r.score > v_me.score or (r.score = v_me.score and r.tiebreak > v_me.tiebreak)))) end);
  end if;

  if scope = 'country' then
    if v_country is null then
      return jsonb_build_object('board', board, 'scope', scope, 'period', period, 'periodKey', v_key, 'rows', '[]'::jsonb,
                                'around', '[]'::jsonb, 'me', null, 'refreshedAt', null, 'needsCountry', true);
    end if;
    v_scope_key := v_country;
  end if;

  select coalesce(jsonb_agg(app.board_row(s.rank, s.user_id, s.score, me) order by s.pos), '[]'), max(s.refreshed_at)
    into v_rows, v_refreshed
    from public.leaderboard_snapshots s
   where s.board = get_leaderboard.board and s.scope = get_leaderboard.scope and s.scope_key = v_scope_key
     and s.period_key = v_key and s.pos <= 100;

  select s.pos into v_my_pos from public.leaderboard_snapshots s
   where s.board = get_leaderboard.board and s.scope = get_leaderboard.scope and s.scope_key = v_scope_key
     and s.period_key = v_key and s.user_id = me;
  if v_my_pos > 100 then
    select coalesce(jsonb_agg(app.board_row(s.rank, s.user_id, s.score, me) order by s.pos), '[]') into v_around
      from public.leaderboard_snapshots s
     where s.board = get_leaderboard.board and s.scope = get_leaderboard.scope and s.scope_key = v_scope_key
       and s.period_key = v_key and s.pos between v_my_pos - 10 and v_my_pos + 10;
  end if;

  return jsonb_build_object('board', board, 'scope', scope, 'period', period, 'periodKey', v_key,
    'refreshedAt', app.utc_iso(v_refreshed), 'rows', v_rows, 'around', v_around,
    'me', case when v_me.score is null then null else jsonb_build_object('score', v_me.score, 'shadow', not v_eligible,
      'rank', 1 + (select count(*) from app.board_ranked(board, period) r
                    where (scope = 'global' or r.country = v_country) and r.user_id <> me
                      and (r.score > v_me.score or (r.score = v_me.score and r.tiebreak > v_me.tiebreak)))) end);
end $$;

-- ---------------------------------------------------------------------------
-- Grants: RPCs for signed-in users only; internals for the service role.
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['send_friend_request(uuid)', 'respond_friend_request(uuid, boolean)', 'remove_friend(uuid)',
                           'block_user(uuid)', 'unblock_user(uuid)', 'list_friends()', 'search_users(text)',
                           'get_friend_feed()', 'give_kudos(bigint)', 'set_notification_prefs(jsonb)',
                           'register_push_token(uuid, text)', 'get_leaderboard(text, text, text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
grant execute on all functions in schema app to service_role;
