-- 0034 — Clan Wars v2 (D-078): groups of 2–4 clans instead of duels, a lobby right after a clan is created, the war
-- Monday 00:00 → Sunday 20:00 UTC, results on Sunday evening and straight into the next lobby.
--
-- * A clan (war on, ≥ 1 member) always has one *active* entry: a lobby for next Monday or a live war.
-- * Mid-week newcomers join an open lobby of next week (< 4 clans, closest rating) or open a new one — so two clans
--   created on Thursday already see each other in the lobby.
-- * Monday 00:00 UTC: lobbies with ≥ 2 clans go live. A clan still alone joins another group (a group of 4 gives up
--   one clan) or another lone clan; if there is nobody at all it moves to the next week.
-- * Sunday 20:00 UTC: ranking (score, then contributors ≥ 50, then who reached the score first), clan trophies
--   (`clans.rating`) by pairwise Elo, K = 30 per opponent (reference `pushly_ref/clan_war_groups.py`, vectors
--   `shared/test-vectors/clan-war/groups.json`, test 104), MVPs, chat lines + push. Then every clan is regrouped by
--   rating into groups of ≤ 4 (sizes as even as possible) for next Monday; existing lobbies with ≥ 2 clans stay.
-- * Points: verified reps with the same day caps as before (`app.clan_war_day_total`), for the clan you are in.
-- The v1 tables (clan_wars, rosters, member_daily) stay as history; their trigger and cron are retired.

create table public.clan_war_groups (
  id uuid primary key default gen_random_uuid(),
  week_start date not null,                       -- the Monday (UTC) the war starts
  status text not null default 'lobby' check (status in ('lobby', 'live', 'finished')),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);
create index clan_war_groups_status_idx on public.clan_war_groups(status, week_start);

create table public.clan_war_entries (
  group_id uuid not null references public.clan_war_groups(id) on delete cascade,
  clan_id uuid not null references public.clans(id) on delete cascade,
  active boolean not null default true,           -- lobby or live; false once finished
  joined_at timestamptz not null default now(),
  moved_weeks int not null default 0,             -- weeks it waited because nobody else was there
  score bigint not null default 0,
  score_at timestamptz,                           -- when the current score was reached (tie-break)
  contributors int not null default 0,
  rank int,
  rating_before int,
  rating_delta int,
  mvp uuid references public.profiles(id) on delete set null,
  primary key (group_id, clan_id)
);
create unique index clan_war_entries_one_active on public.clan_war_entries(clan_id) where active;
create index clan_war_entries_clan_idx on public.clan_war_entries(clan_id, joined_at desc);

create table public.clan_war_points (
  group_id uuid not null references public.clan_war_groups(id) on delete cascade,
  clan_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,                              -- UTC
  raw_reps int not null default 0,
  counted_reps int not null default 0,
  primary key (group_id, user_id, day)
);
create index clan_war_points_clan_idx on public.clan_war_points(group_id, clan_id);

create table public.clan_war_group_feed (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.clan_war_groups(id) on delete cascade,
  clan_id uuid not null,
  user_id uuid references public.profiles(id) on delete cascade,
  points int not null check (points > 0),
  created_at timestamptz not null default now()
);
create index clan_war_group_feed_idx on public.clan_war_group_feed(group_id, created_at desc);

do $$
declare t text;
begin
  foreach t in array array['clan_war_groups', 'clan_war_entries', 'clan_war_points', 'clan_war_group_feed'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);   -- read through the RPCs only
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Pure rules (reference pushly_ref/clan_war_groups.py)
-- ---------------------------------------------------------------------------------------------------------------

-- War window: Monday 00:00 UTC → Sunday 20:00 UTC (results on Sunday evening, D-078).
create or replace function app.war_starts_at(week date) returns timestamptz
language sql immutable as $$ select week::timestamp at time zone 'UTC' $$;

create or replace function app.war_ends_at(week date) returns timestamptz
language sql immutable as $$ select (week + 6)::timestamp at time zone 'UTC' + interval '20 hours' $$;

-- [{id, rating, score, contributors, scoreAtMs}] → {id: {rank, delta}}
create or replace function app.clan_war_group_outcome(entries jsonb) returns jsonb
language sql immutable as $$
  with r as (
    select e->>'id' as id, (e->>'rating')::int as rating,
           rank() over (order by (e->>'score')::bigint desc, (e->>'contributors')::int desc,
                                 case when (e->>'score')::bigint > 0 then (e->>'scoreAtMs')::bigint end asc nulls last) as rk
      from jsonb_array_elements(entries) e)
  select coalesce(jsonb_object_agg(a.id, jsonb_build_object('rank', a.rk, 'delta', coalesce(round(d.s::numeric)::int, 0))), '{}')
    from r a
    left join lateral (
      select sum(30 * ((case when a.rk < b.rk then 1 when a.rk = b.rk then 0.5 else 0 end)
                       - 1 / (1 + power(10::double precision, (b.rating - a.rating) / 400.0)))) as s
        from r b where b.id <> a.id) d on true
$$;

-- What a clan can win (1st, everyone else behind) or lose (last) against these ratings.
create or replace function app.clan_war_stakes(ratings jsonb, me text) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'win', coalesce(round(sum(30 * (1 - 1 / (1 + power(10::double precision, ((value)::int - (ratings->>me)::int) / 400.0))))::numeric)::int, 0),
    'last', coalesce(round(sum(30 * (0 - 1 / (1 + power(10::double precision, ((value)::int - (ratings->>me)::int) / 400.0))))::numeric)::int, 0))
  from jsonb_each_text(ratings) where key <> me
$$;

-- Even group sizes, ≤ 4, never a group of 1 when there are ≥ 2 clans.
create or replace function app.clan_war_group_sizes(n int) returns int[]
language sql immutable as $$
  with g as (select ceil(n / 4.0)::int as groups)
  select coalesce(array_agg(case when i <= n % g.groups then n / g.groups + 1 else n / g.groups end order by i), '{}')
    from g, generate_series(1, greatest(g.groups, 0)) i where n > 0
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Lobby placement
-- ---------------------------------------------------------------------------------------------------------------

create or replace function app.clan_war_eligible(cid uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (select 1 from public.clans c where c.id = cid and c.war_enabled and c.member_count >= 1)
$$;

-- Opponent names of a group for chat lines / pushes, without `cid`.
create or replace function app.clan_war_rivals(gid uuid, cid uuid) returns text
language sql stable security definer set search_path = public, app as $$
  select coalesce(string_agg(c.name::text, ', ' order by c.rating desc), '')
    from public.clan_war_entries e join public.clans c on c.id = e.clan_id
   where e.group_id = gid and e.clan_id <> cid
$$;

-- Puts a clan without an active entry into a lobby for next Monday: an open lobby (< 4) with the closest average
-- rating (fuller first on ties), or a new one. Returns the group id (null when not eligible / already placed).
create or replace function app.clan_war_place(cid uuid, now_at timestamptz default now()) returns uuid
language plpgsql security definer set search_path = public, app as $$
declare
  v_week date := app.war_week_start(now_at) + 7;
  v_rating int;
  v_gid uuid;
begin
  if not app.clan_war_eligible(cid) or exists (select 1 from public.clan_war_entries where clan_id = cid and active) then
    return null;
  end if;
  select rating into v_rating from public.clans where id = cid;
  select g.id into v_gid
    from public.clan_war_groups g
    join public.clan_war_entries e on e.group_id = g.id
    join public.clans c on c.id = e.clan_id
   where g.status = 'lobby' and g.week_start = v_week
   group by g.id
  having count(*) < 4
   order by abs(avg(c.rating) - v_rating), count(*) desc, g.id
   limit 1;
  if v_gid is null then
    insert into public.clan_war_groups (week_start) values (v_week) returning id into v_gid;
  end if;
  insert into public.clan_war_entries (group_id, clan_id) values (v_gid, cid);
  perform app.clan_system_message(cid,
    case when app.clan_war_rivals(v_gid, cid) = '' then
           '⚔️ We''re in the Clan War lobby. Opponents join during the week — the war starts on Monday.'
         else '⚔️ Clan War lobby: we''ll fight ' || app.clan_war_rivals(v_gid, cid) || '. The war starts on Monday.' end,
    jsonb_build_object('event', 'war_lobby', 'warId', v_gid));
  perform app.clan_system_message(e.clan_id, '⚔️ ' || (select name from public.clans where id = cid) ||
                                  ' joined our Clan War lobby.', jsonb_build_object('event', 'war_lobby', 'warId', v_gid))
     from public.clan_war_entries e where e.group_id = v_gid and e.clan_id <> cid;
  return v_gid;
end $$;

-- Sunday regroup: every unplaced eligible clan + clans alone in a next-week lobby, sorted by rating, cut into even
-- groups of ≤ 4. Lobbies that already have ≥ 2 clans stay as they are. A single leftover clan is placed normally.
create or replace function app.clan_war_regroup(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_week date := app.war_week_start(now_at) + 7;
  v_ids uuid[];
  v_sizes int[];
  v_pos int := 1;
  v_size int;
  v_gid uuid;
  v_n int := 0;
  i int;
begin
  -- free the clans sitting alone in a next-week lobby
  delete from public.clan_war_groups g
   where g.status = 'lobby' and g.week_start = v_week
     and (select count(*) from public.clan_war_entries e where e.group_id = g.id) = 1;
  select array_agg(c.id order by c.rating desc, c.id) into v_ids
    from public.clans c
   where c.war_enabled and c.member_count >= 1
     and not exists (select 1 from public.clan_war_entries e where e.clan_id = c.id and e.active);
  if v_ids is null then return 0; end if;
  if array_length(v_ids, 1) = 1 then
    perform app.clan_war_place(v_ids[1], now_at);
    return 1;
  end if;
  v_sizes := app.clan_war_group_sizes(array_length(v_ids, 1));
  foreach v_size in array v_sizes loop
    insert into public.clan_war_groups (week_start) values (v_week) returning id into v_gid;
    for i in v_pos .. v_pos + v_size - 1 loop
      insert into public.clan_war_entries (group_id, clan_id) values (v_gid, v_ids[i]);
      v_n := v_n + 1;
    end loop;
    v_pos := v_pos + v_size;
    perform app.clan_system_message(e.clan_id,
      '⚔️ Next Clan War: we''ll fight ' || app.clan_war_rivals(v_gid, e.clan_id) || '. It starts on Monday.',
      jsonb_build_object('event', 'war_lobby', 'warId', v_gid))
      from public.clan_war_entries e where e.group_id = v_gid;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Start (Monday 00:00 UTC) and finish (Sunday 20:00 UTC)
-- ---------------------------------------------------------------------------------------------------------------

create or replace function app.clan_war_start(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_week date := app.war_week_start(now_at);
  s record;
  v_target uuid;
  v_victim uuid;
  v_alone uuid;
  v_n int := 0;
  lg record;
  m record;
begin
  if now_at >= app.war_ends_at(v_week) then return 0; end if;   -- too late for this week (Sunday evening)
  -- lobbies whose Monday has come but nobody could join in time
  update public.clan_war_groups set week_start = v_week where status = 'lobby' and week_start < v_week;
  -- lone clans: join a group of 2–3, else take one clan from a group of 4, else pair with another lone clan
  for s in select g.id gid, e.clan_id, c.rating from public.clan_war_groups g
             join public.clan_war_entries e on e.group_id = g.id join public.clans c on c.id = e.clan_id
            where g.status = 'lobby' and g.week_start = v_week
              and (select count(*) from public.clan_war_entries x where x.group_id = g.id) = 1
            order by c.rating desc loop
    continue when (select count(*) from public.clan_war_entries x where x.group_id = s.gid) <> 1;
    select g.id into v_target from public.clan_war_groups g
      join public.clan_war_entries e on e.group_id = g.id join public.clans c on c.id = e.clan_id
     where g.status = 'lobby' and g.week_start = v_week and g.id <> s.gid
     group by g.id having count(*) between 2 and 3
     order by abs(avg(c.rating) - s.rating), g.id limit 1;
    if v_target is not null then
      update public.clan_war_entries set group_id = v_target where group_id = s.gid and clan_id = s.clan_id;
      delete from public.clan_war_groups where id = s.gid;
      v_target := null;
      continue;
    end if;
    select e.clan_id into v_victim from public.clan_war_groups g
      join public.clan_war_entries e on e.group_id = g.id join public.clans c on c.id = e.clan_id
     where g.status = 'lobby' and g.week_start = v_week and g.id <> s.gid
       and (select count(*) from public.clan_war_entries x where x.group_id = g.id) = 4
     order by abs(c.rating - s.rating), e.clan_id limit 1;
    if v_victim is not null then
      update public.clan_war_entries set group_id = s.gid where clan_id = v_victim and active;
      v_victim := null;
      continue;
    end if;
    select g.id into v_alone from public.clan_war_groups g
      join public.clan_war_entries e on e.group_id = g.id join public.clans c on c.id = e.clan_id
     where g.status = 'lobby' and g.week_start = v_week and g.id <> s.gid
     group by g.id having count(*) = 1
     order by abs(min(c.rating) - s.rating), g.id limit 1;
    if v_alone is not null then
      update public.clan_war_entries set group_id = s.gid where group_id = v_alone;
      delete from public.clan_war_groups where id = v_alone;
      v_alone := null;
    end if;
  end loop;
  -- still alone → next week
  for lg in select x.id from public.clan_war_groups x
            where x.status = 'lobby' and x.week_start = v_week
              and (select count(*) from public.clan_war_entries e where e.group_id = x.id) = 1 loop
    update public.clan_war_groups set week_start = v_week + 7 where id = lg.id;
    update public.clan_war_entries set moved_weeks = moved_weeks + 1 where group_id = lg.id;
    perform app.clan_system_message(e.clan_id,
      'No opponent was free this week, so our Clan War moves to next Monday. Invite friends — any clan can join the lobby.',
      jsonb_build_object('event', 'war_moved', 'warId', lg.id))
      from public.clan_war_entries e where e.group_id = lg.id;
  end loop;
  -- go live
  for lg in select x.id from public.clan_war_groups x where x.status = 'lobby' and x.week_start = v_week loop
    update public.clan_war_groups set status = 'live', started_at = now_at where id = lg.id;
    update public.clan_war_entries e set rating_before = c.rating, score = 0, score_at = null
      from public.clans c where c.id = e.clan_id and e.group_id = lg.id;
    for m in select e.clan_id, c.name from public.clan_war_entries e join public.clans c on c.id = e.clan_id
              where e.group_id = lg.id loop
      perform app.clan_system_message(m.clan_id, '⚔️ The Clan War has started! We fight ' ||
        app.clan_war_rivals(lg.id, m.clan_id) || ' until Sunday 20:00 UTC.', jsonb_build_object('event', 'war_started', 'warId', lg.id));
      perform app.enqueue_push(cm.user_id, 'clan_war_started', 'clan',
        jsonb_build_object('clanName', m.name, 'opponents', app.clan_war_rivals(lg.id, m.clan_id), 'warId', lg.id),
        'clanwar:' || lg.id)
        from public.clan_members cm where cm.clan_id = m.clan_id;
    end loop;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

create or replace function app.clan_war_finish(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  fg record;
  fe record;
  v_outcome jsonb;
  v_of int;
  v_rank int;
  v_delta int;
  v_n int := 0;
begin
  for fg in select * from public.clan_war_groups x where x.status = 'live' and app.war_ends_at(x.week_start) <= now_at
            for update loop
    update public.clan_war_entries x set contributors = (
        select count(*) from (select p.user_id from public.clan_war_points p
                               where p.group_id = fg.id and p.clan_id = x.clan_id group by p.user_id
                              having sum(p.counted_reps) >= 50) c),
      mvp = (select p.user_id from public.clan_war_points p where p.group_id = fg.id and p.clan_id = x.clan_id
              group by p.user_id order by sum(p.counted_reps) desc, p.user_id limit 1)
     where x.group_id = fg.id;
    select jsonb_agg(jsonb_build_object('id', x.clan_id, 'rating', coalesce(x.rating_before, c.rating), 'score', x.score,
                     'contributors', x.contributors,
                     'scoreAtMs', (extract(epoch from x.score_at) * 1000)::bigint))
      into v_outcome
      from public.clan_war_entries x join public.clans c on c.id = x.clan_id where x.group_id = fg.id;
    v_outcome := app.clan_war_group_outcome(coalesce(v_outcome, '[]'));
    select count(*) into v_of from public.clan_war_entries where group_id = fg.id;
    for fe in select x.*, c.name from public.clan_war_entries x join public.clans c on c.id = x.clan_id where x.group_id = fg.id loop
      v_rank := (v_outcome->(fe.clan_id::text)->>'rank')::int;
      v_delta := (v_outcome->(fe.clan_id::text)->>'delta')::int;
      update public.clan_war_entries set rank = v_rank, rating_delta = v_delta, active = false
       where group_id = fg.id and clan_id = fe.clan_id;
      update public.clans set rating = greatest(0, rating + v_delta) where id = fe.clan_id;
      perform app.clan_system_message(fe.clan_id,
        case when v_rank = 1 and v_of > 1 then '🏆 We won the Clan War! '
             else 'Clan War over — we finished #' || v_rank || ' of ' || v_of || '. ' end ||
        case when v_delta >= 0 then '+' else '' end || v_delta || ' clan trophies. Next war: Monday.',
        jsonb_build_object('event', 'war_ended', 'warId', fg.id, 'rank', v_rank, 'of', v_of, 'delta', v_delta));
      perform app.enqueue_push(cm.user_id, 'clan_war_result', 'clan',
        jsonb_build_object('rank', v_rank, 'of', v_of, 'delta', v_delta, 'warId', fg.id), 'clanwar:' || fg.id)
        from public.clan_members cm where cm.clan_id = fe.clan_id;
    end loop;
    update public.clan_war_groups set status = 'finished', finished_at = now_at where id = fg.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Every 5 minutes: finish due wars (→ regroup everybody for next week), start due lobbies, place newcomers.
create or replace function app.clan_war_tick(now_at timestamptz default now()) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  c record;
begin
  if app.clan_war_finish(now_at) > 0 then
    perform app.clan_war_regroup(now_at);
  end if;
  perform app.clan_war_start(now_at);
  for c in select x.id from public.clans x
            where x.war_enabled and x.member_count >= 1
              and not exists (select 1 from public.clan_war_entries e where e.clan_id = x.id and e.active)
            order by x.created_at loop
    perform app.clan_war_place(c.id, now_at);
  end loop;
  -- war turned off: leave the lobby (never a live war)
  delete from public.clan_war_entries e using public.clan_war_groups g, public.clans x
   where g.id = e.group_id and x.id = e.clan_id and e.active and g.status = 'lobby' and not x.war_enabled;
  delete from public.clan_war_groups g
   where g.status = 'lobby' and not exists (select 1 from public.clan_war_entries e where e.group_id = g.id);
end $$;

-- A new clan (or war switched on) gets its lobby at once.
create or replace function app.on_clan_war_eligibility() returns trigger
language plpgsql security definer set search_path = public, app as $$
begin
  if new.war_enabled and new.member_count >= 1 then
    perform app.clan_war_place(new.id);
  elsif not new.war_enabled then
    delete from public.clan_war_entries e using public.clan_war_groups g
     where g.id = e.group_id and e.clan_id = new.id and e.active and g.status = 'lobby';
  end if;
  return new;
end $$;
create trigger clans_war_eligibility after update of war_enabled, member_count on public.clans
  for each row when (old.war_enabled is distinct from new.war_enabled or (old.member_count = 0 and new.member_count > 0))
  execute function app.on_clan_war_eligibility();

-- ---------------------------------------------------------------------------------------------------------------
-- Points (replaces the v1 trigger)
-- ---------------------------------------------------------------------------------------------------------------

drop trigger if exists user_stats_daily_war on public.user_stats_daily;

create or replace function app.on_stats_daily_war_v2() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  v_cid uuid;
  v_gid uuid;
  v_trust int;
  v_counted int;
  v_before int;
  v_total bigint;
  v_leader_before uuid;
  v_leader_after uuid;
begin
  select clan_id into v_cid from public.clan_members where user_id = new.user_id;
  if v_cid is null then return new; end if;
  select g.id into v_gid from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
   where e.clan_id = v_cid and e.active and g.status = 'live'
     and g.week_start = app.war_week_start(new.day::timestamp at time zone 'UTC');
  if v_gid is null then return new; end if;
  select trust_score into v_trust from public.profiles where id = new.user_id;
  v_counted := case when v_trust < 30 then 0 else app.clan_war_day_total(new.reps_total, v_trust < 50) end;
  select coalesce((select counted_reps from public.clan_war_points p
                    where p.group_id = v_gid and p.user_id = new.user_id and p.day = new.day), 0) into v_before;
  insert into public.clan_war_points as p (group_id, clan_id, user_id, day, raw_reps, counted_reps)
  values (v_gid, v_cid, new.user_id, new.day, new.reps_total, v_counted)
  on conflict (group_id, user_id, day) do update set raw_reps = excluded.raw_reps, counted_reps = excluded.counted_reps;
  if v_counted <= v_before then return new; end if;
  insert into public.clan_war_group_feed (group_id, clan_id, user_id, points) values (v_gid, v_cid, new.user_id, v_counted - v_before);
  select clan_id into v_leader_before from public.clan_war_entries where group_id = v_gid and score > 0
   order by score desc, score_at asc nulls last limit 1;
  select coalesce(sum(counted_reps), 0) into v_total from public.clan_war_points where group_id = v_gid and clan_id = v_cid;
  update public.clan_war_entries set score = v_total, score_at = now() where group_id = v_gid and clan_id = v_cid;
  select clan_id into v_leader_after from public.clan_war_entries where group_id = v_gid
   order by score desc, score_at asc nulls last limit 1;
  if v_leader_after = v_cid and v_leader_before is distinct from v_cid
     and not exists (select 1 from public.clan_events ev where ev.type = 'war_lead' and ev.payload->>'warId' = v_gid::text
                       and ev.created_at > now() - interval '1 hour') then
    insert into public.clan_events (clan_id, actor, type, payload) values (v_cid, new.user_id, 'war_lead', jsonb_build_object('warId', v_gid));
    perform app.clan_system_message(v_cid, '⚔️ We took the lead in the Clan War!', jsonb_build_object('event', 'war_lead', 'warId', v_gid));
    if v_leader_before is not null then
      perform app.clan_system_message(v_leader_before,
        '⚠️ ' || (select name from public.clans where id = v_cid) || ' overtook us in the Clan War — time to push!',
        jsonb_build_object('event', 'war_lost_lead', 'warId', v_gid));
    end if;
  end if;
  return new;
end $$;
create trigger user_stats_daily_war_v2 after insert or update of reps_total on public.user_stats_daily
  for each row execute function app.on_stats_daily_war_v2();

-- ---------------------------------------------------------------------------------------------------------------
-- Read API
-- ---------------------------------------------------------------------------------------------------------------

-- One war (lobby / live / finished) as seen from clan `cid` (clan-war-state.schema.json).
create or replace function app.clan_war_group_json(gid uuid, cid uuid, me uuid) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  g public.clan_war_groups;
  v_ratings jsonb;
  v_today int;
  v_rally timestamptz;
  v_mine public.clan_war_entries;
begin
  select * into g from public.clan_war_groups where id = gid;
  if not found then return null; end if;
  select * into v_mine from public.clan_war_entries where group_id = gid and clan_id = cid;
  select jsonb_object_agg(e.clan_id::text, coalesce(e.rating_before, c.rating)) into v_ratings
    from public.clan_war_entries e join public.clans c on c.id = e.clan_id where e.group_id = gid;
  select coalesce(sum(p.raw_reps), 0) into v_today from public.clan_war_points p
   where p.group_id = gid and p.user_id = me and p.day = (now() at time zone 'UTC')::date;
  select last_rally_at into v_rally from public.clans where id = cid;
  return jsonb_build_object(
    'id', g.id, 'status', g.status, 'weekStart', g.week_start,
    'startsAt', app.utc_iso(app.war_starts_at(g.week_start)), 'endsAt', app.utc_iso(app.war_ends_at(g.week_start)),
    'movedWeeks', coalesce(v_mine.moved_weeks, 0),
    'clans', (select coalesce(jsonb_agg(jsonb_build_object(
                'clan', app.clan_json(e.clan_id, me), 'score', e.score, 'isMine', e.clan_id = cid,
                'rank', case when g.status = 'finished' then e.rank else e.live_rank end,
                'ratingDelta', e.rating_delta,
                'stakes', case when g.status <> 'finished' then app.clan_war_stakes(v_ratings, e.clan_id::text) end,
                'mvp', case when e.mvp is not null then app.user_card(e.mvp, me) end)
                order by case when g.status = 'finished' then e.rank else e.live_rank end, e.joined_at), '[]')
                from (select x.*, rank() over (order by x.score desc) as live_rank
                        from public.clan_war_entries x where x.group_id = gid) e),
    'result', case when g.status = 'finished' then jsonb_build_object(
                'rank', v_mine.rank, 'of', (select count(*) from public.clan_war_entries where group_id = gid),
                'ratingDelta', v_mine.rating_delta) end,
    'myToday', jsonb_build_object('raw', v_today, 'counted', app.clan_war_day_total(v_today, false), 'fullCap', 200, 'halfCap', 400),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(s.user_id, me), 'reps', s.t) order by s.t desc), '[]')
              from (select p.user_id, sum(p.counted_reps) t from public.clan_war_points p
                     where p.group_id = gid and p.clan_id = cid group by 1 order by 2 desc limit 5) s),
    'feed', (select coalesce(jsonb_agg(jsonb_build_object('clanId', f.clan_id, 'clanName', c.name, 'mine', f.clan_id = cid,
                                                          'username', coalesce(p.username, 'Deleted user'), 'points', f.points,
                                                          'at', app.utc_iso(f.created_at)) order by f.created_at desc, f.id desc), '[]')
               from (select * from public.clan_war_group_feed x where x.group_id = gid order by x.created_at desc, x.id desc limit 15) f
               left join public.profiles p on p.id = f.user_id left join public.clans c on c.id = f.clan_id),
    'rally', jsonb_build_object('available', g.status = 'live' and app.my_clan_id(me) = cid
                                              and (v_rally is null or v_rally <= now() - interval '6 hours'),
                                'nextAt', case when v_rally > now() - interval '6 hours' then app.utc_iso(v_rally + interval '6 hours') end));
end $$;

-- {current: the lobby or live war, last: the latest finished war} for my clan (or `clan_id`).
create or replace function public.get_clan_war_state(clan_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := coalesce(clan_id, app.my_clan_id(me));
  v_cur uuid;
  v_last uuid;
begin
  if v_cid is null then return null; end if;
  select e.group_id into v_cur from public.clan_war_entries e where e.clan_id = v_cid and e.active limit 1;
  select e.group_id into v_last from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
   where e.clan_id = v_cid and g.status = 'finished' order by g.finished_at desc limit 1;
  return jsonb_build_object('current', case when v_cur is not null then app.clan_war_group_json(v_cur, v_cid, me) end,
                            'last', case when v_last is not null then app.clan_war_group_json(v_last, v_cid, me) end);
end $$;

-- Finished wars of a clan, newest first (clan-war-results.schema.json).
create or replace function public.get_clan_war_results(clan_id uuid default null, lim int default 20) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := coalesce(clan_id, app.my_clan_id(me));
begin
  if v_cid is null then return '[]'; end if;
  return coalesce((select jsonb_agg(x.j order by x.fin desc) from (
    select g.finished_at fin, jsonb_build_object('id', g.id, 'weekStart', g.week_start, 'rank', e.rank,
      'of', (select count(*) from public.clan_war_entries o where o.group_id = g.id), 'score', e.score,
      'ratingDelta', e.rating_delta,
      'clans', (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'badge', c.badge,
                                                    'score', o.score, 'rank', o.rank, 'isMine', o.clan_id = v_cid) order by o.rank, o.score desc)
                  from public.clan_war_entries o join public.clans c on c.id = o.clan_id where o.group_id = g.id)) j
      from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
     where e.clan_id = v_cid and g.status = 'finished'
     order by g.finished_at desc limit greatest(1, least(coalesce(lim, 20), 52))) x), '[]');
end $$;

-- get_clan: the v2 war state; the v1 `war` card is retired (null).
create or replace function public.get_clan(clan_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := coalesce(clan_id, app.my_clan_id(me));
  v_war uuid;
  v_role public.clan_role;
begin
  if v_cid is null then return null; end if;
  if not exists (select 1 from public.clans where id = v_cid) then raise exception 'clan not found' using errcode = 'P0002'; end if;
  select e.group_id into v_war from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
   where e.clan_id = v_cid and e.active and g.status = 'live';
  select role into v_role from public.clan_members where user_id = me and clan_members.clan_id = v_cid;
  return app.clan_json(v_cid, me) || jsonb_build_object(
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(m.user_id, me), 'role', m.role,
                  'joinedAt', app.utc_iso(m.joined_at),
                  'repsToday', coalesce((select reps_total from public.user_stats_daily d
                                          where d.user_id = m.user_id and d.day = (now() at time zone 'UTC')::date), 0),
                  'warReps', coalesce((select sum(counted_reps) from public.clan_war_points x
                                        where x.group_id = v_war and x.user_id = m.user_id and x.clan_id = v_cid), 0))
                  order by app.role_rank(m.role) desc, lower(p.username)), '[]')
                  from public.clan_members m join public.profiles p on p.id = m.user_id where m.clan_id = v_cid),
    'requests', case when app.role_rank(coalesce(v_role, 'member')) >= 2 then
                  (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(r.user_id, me), 'message', r.message,
                     'createdAt', app.utc_iso(r.created_at)) order by r.created_at), '[]')
                     from public.clan_join_requests r where r.clan_id = v_cid and r.status = 'pending')
                else '[]'::jsonb end,
    'war', null,
    'warState', public.get_clan_war_state(v_cid));
end $$;

-- Rally on the v2 war: the gap is to the leader (or my lead over #2).
create or replace function public.clan_rally() returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := app.my_clan_id(me);
  v_gid uuid;
  v_mine bigint;
  v_best_other bigint;
  v_gap bigint;
  v_name text;
  m record;
begin
  if v_cid is null then raise exception 'not in a clan' using errcode = 'P0002', hint = 'no_clan'; end if;
  select e.group_id, e.score into v_gid, v_mine from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
   where e.clan_id = v_cid and e.active and g.status = 'live';
  if v_gid is null then raise exception 'no live war' using errcode = 'P0001', hint = 'no_war'; end if;
  update public.clans set last_rally_at = now()
   where id = v_cid and (last_rally_at is null or last_rally_at <= now() - interval '6 hours');
  if not found then raise exception 'rally cooldown' using errcode = 'P0001', hint = 'rally_cooldown'; end if;
  select max(score) into v_best_other from public.clan_war_entries where group_id = v_gid and clan_id <> v_cid;
  v_gap := v_mine - coalesce(v_best_other, 0);
  select username into v_name from public.profiles where id = me;
  perform app.clan_system_message(v_cid,
    '📣 ' || coalesce(v_name, 'A member') || ' calls everyone to the war! ' ||
    case when v_gap < 0 then 'We are ' || (-v_gap) || ' behind the leader.'
         when v_gap > 0 then 'We lead by ' || v_gap || ' — keep it up!'
         else 'It''s tied at the top!' end,
    jsonb_build_object('event', 'rally', 'warId', v_gid, 'userId', me));
  for m in select user_id from public.clan_members where clan_id = v_cid and user_id <> me loop
    perform app.enqueue_push(m.user_id, 'clan_rally', 'clan',
      jsonb_build_object('username', v_name, 'gap', v_gap, 'warId', v_gid, 'clanId', v_cid), 'rally:' || v_cid);
  end loop;
  return public.get_clan_war_state(v_cid);
end $$;

-- Clans board 'week' = this week's live war score.
create or replace function public.get_clan_leaderboard(period text default 'rating', country text default null) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_mine uuid := app.my_clan_id(me);
begin
  if period not in ('rating', 'week') then raise exception 'unknown period' using errcode = '22023'; end if;
  return (select jsonb_build_object('period', period, 'rows', coalesce(jsonb_agg(jsonb_build_object('rank', r.rk, 'score', r.score,
            'isMine', r.id = v_mine, 'clan', app.clan_json(r.id, me)) order by r.rk, r.id), '[]'))
    from (select c.id, s.score, rank() over (order by s.score desc) rk
            from public.clans c
            cross join lateral (select case when period = 'rating' then c.rating::bigint
                                            else coalesce((select e.score from public.clan_war_entries e
                                                             join public.clan_war_groups g on g.id = e.group_id
                                                            where e.clan_id = c.id and e.active and g.status = 'live'), 0) end score) s
           where get_clan_leaderboard.country is null or c.country = upper(get_clan_leaderboard.country)
           order by s.score desc limit 100) r);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Move the v1 week over: running duels become live groups (scores, points and feed carried over); solo "byes" end.
-- ---------------------------------------------------------------------------------------------------------------
do $$
declare
  w public.clan_wars;
  v_gid uuid;
begin
  for w in select * from public.clan_wars where status = 'live' loop
    if w.clan_b is not null and not exists (select 1 from public.clan_war_entries where clan_id in (w.clan_a, w.clan_b) and active) then
      insert into public.clan_war_groups (week_start, status, started_at) values (w.week_start, 'live', now()) returning id into v_gid;
      insert into public.clan_war_entries (group_id, clan_id, score, score_at, rating_before)
      select v_gid, x.cid, x.sc, x.at, (select rating from public.clans where id = x.cid)
        from (values (w.clan_a, w.score_a, w.score_a_at), (w.clan_b, w.score_b, w.score_b_at)) x(cid, sc, at);
      insert into public.clan_war_points (group_id, clan_id, user_id, day, raw_reps, counted_reps)
      select v_gid, ro.clan_id, d.user_id, d.day, d.raw_reps, d.counted_reps
        from public.clan_war_member_daily d join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
       where d.war_id = w.id;
      insert into public.clan_war_group_feed (group_id, clan_id, user_id, points, created_at)
      select v_gid, f.clan_id, f.user_id, f.points, f.created_at from public.clan_war_feed f where f.war_id = w.id;
    end if;
    update public.clan_wars set status = 'finished', finished_at = now(),
      result = coalesce(result, '{}') || jsonb_build_object('reason', 'moved_to_v2') where id = w.id;
  end loop;
end $$;

-- lobbies for every eligible clan right away
select app.clan_war_tick();

do $$
declare
  f text;
begin
  foreach f in array array['get_clan_war_state(uuid)', 'get_clan_war_results(uuid, int)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
grant execute on all functions in schema app to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then return; end if;
  if exists (select 1 from cron.job where jobname = 'pushly-clan-wars') then perform cron.unschedule('pushly-clan-wars'); end if;
  perform cron.schedule('pushly-clan-war-tick', '*/5 * * * *', 'select app.clan_war_tick()');
end $$;
