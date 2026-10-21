-- 0015 — clans, roles, join flow, chat, weekly Clan Wars (doc 09), roadmap P8-01 / P8-03 / P8-05 / P8-06 backend.
-- War rep counting mirrors tools/reference/pushly_ref/clan_war.py (vectors shared/test-vectors/clan-war, test 091).

create table public.clans (
  id uuid primary key default gen_random_uuid(),
  name citext unique not null check (char_length(name) between 3 and 24),
  tag citext unique not null check (tag ~ '^[A-Z0-9]{3,5}$'),
  badge jsonb not null default '{}',
  description text not null default '' check (char_length(description) <= 200),
  join_policy public.join_policy not null default 'open',
  min_trophies int not null default 0 check (min_trophies >= 0),
  country char(2) check (country ~ '^[A-Z]{2}$'),
  war_enabled boolean not null default true,
  rating int not null default 1000,
  member_count smallint not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.clan_members (
  clan_id uuid not null references public.clans(id) on delete cascade,
  user_id uuid not null unique references public.profiles(id) on delete cascade,   -- one clan per user
  role public.clan_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (clan_id, user_id)
);
create unique index clan_members_one_leader on public.clan_members(clan_id) where role = 'leader';

create table public.clan_join_requests (
  clan_id uuid not null references public.clans(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text check (char_length(message) <= 200),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  primary key (clan_id, user_id)
);

create table public.clan_messages (
  id bigint generated always as identity primary key,
  clan_id uuid not null references public.clans(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,     -- null = system message
  kind text not null default 'text' check (kind in ('text', 'system', 'kudos')),
  body text check (char_length(body) <= 500),
  meta jsonb,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index clan_messages_clan_idx on public.clan_messages(clan_id, created_at desc);

create table public.clan_events (
  id bigint generated always as identity primary key,
  clan_id uuid,
  actor uuid,
  type text not null,
  payload jsonb,
  created_at timestamptz not null default now()
);

create table public.clan_wars (
  id uuid primary key default gen_random_uuid(),
  week_start date not null,                       -- Monday (UTC)
  clan_a uuid not null references public.clans(id) on delete cascade,
  clan_b uuid references public.clans(id) on delete cascade,          -- null = bye
  status public.war_status not null default 'live',
  score_a bigint not null default 0,
  score_b bigint not null default 0,
  score_a_at timestamptz,                         -- when the current score was reached (tie-break)
  score_b_at timestamptz,
  winner uuid,
  result jsonb,
  finished_at timestamptz,
  unique (week_start, clan_a)
);
create index clan_wars_b_idx on public.clan_wars(week_start, clan_b);

create table public.clan_war_rosters (
  war_id uuid not null references public.clan_wars(id) on delete cascade,
  clan_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  left_at timestamptz,
  primary key (war_id, user_id)
);
create index clan_war_rosters_user_idx on public.clan_war_rosters(user_id);

create table public.clan_war_member_daily (
  war_id uuid not null references public.clan_wars(id) on delete cascade,
  user_id uuid not null,
  day date not null,                              -- UTC
  raw_reps int not null default 0,
  counted_reps int not null default 0,
  primary key (war_id, user_id, day)
);

do $$
declare t text;
begin
  foreach t in array array['clans', 'clan_members', 'clan_join_requests', 'clan_messages', 'clan_events', 'clan_wars',
                           'clan_war_rosters', 'clan_war_member_daily'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
revoke all on public.clan_events from authenticated;

create or replace function app.my_clan_id(uid uuid) returns uuid
language sql stable security definer set search_path = public, app as $$
  select clan_id from public.clan_members where user_id = uid
$$;

create policy clans_read on public.clans for select to authenticated using (true);
create policy clan_members_read on public.clan_members for select to authenticated using (true);
create policy clan_requests_read on public.clan_join_requests for select to authenticated
  using (user_id = auth.uid() or clan_id = app.my_clan_id(auth.uid()));
-- chat: members only (Realtime postgres changes use this policy)
create policy clan_messages_members on public.clan_messages for select to authenticated
  using (clan_id = app.my_clan_id(auth.uid()) and deleted_at is null);
create policy clan_wars_read on public.clan_wars for select to authenticated using (true);
create policy clan_war_rosters_read on public.clan_war_rosters for select to authenticated using (true);
create policy clan_war_daily_read on public.clan_war_member_daily for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- War rep counting (clan_war.py)
-- ---------------------------------------------------------------------------
create or replace function app.clan_war_day_total(raw_reps int, low_trust boolean) returns int
language plpgsql immutable as $$
declare
  v int;
begin
  if raw_reps < 0 then raise exception 'negative reps' using errcode = '22023'; end if;
  v := least(raw_reps, 200) + greatest(0, least(raw_reps, 400) - 200) / 2;
  return case when low_trust then v / 2 else v end;
end $$;

create or replace function app.clan_war_count(reps_today_before int, new_reps int, low_trust boolean) returns int
language sql immutable as $$
  select app.clan_war_day_total(reps_today_before + new_reps, low_trust) - app.clan_war_day_total(reps_today_before, low_trust)
$$;

-- ---------------------------------------------------------------------------
-- Text rules: tiny profanity list (names are rejected, chat is masked). Server-side only.
-- ---------------------------------------------------------------------------
create or replace function app.profanity_words() returns text[]
language sql immutable as $$
  select array['fuck', 'shit', 'cunt', 'nigger', 'faggot', 'bitch', 'whore', 'kurva', 'pica', 'kokot', 'debil', 'zmrd']
$$;

create or replace function app.has_profanity(t text) returns boolean
language sql immutable as $$
  select exists (select 1 from unnest(app.profanity_words()) w where lower(coalesce(t, '')) like '%' || w || '%')
$$;

create or replace function app.mask_profanity(t text) returns text
language plpgsql immutable as $$
declare
  w text;
  v text := t;
begin
  foreach w in array app.profanity_words() loop
    v := regexp_replace(v, w, repeat('*', length(w)), 'gi');
  end loop;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Roles (doc 09 §2)
-- ---------------------------------------------------------------------------
create or replace function app.role_rank(r public.clan_role) returns int
language sql immutable as $$ select case r when 'leader' then 4 when 'co_leader' then 3 when 'elder' then 2 else 1 end $$;

create or replace function app.my_membership(me uuid) returns public.clan_members
language plpgsql stable security definer set search_path = public, app as $$
declare
  m public.clan_members;
begin
  select * into m from public.clan_members where user_id = me;
  if not found then raise exception 'not in a clan' using errcode = 'P0002'; end if;
  return m;
end $$;

create or replace function app.clan_system_message(cid uuid, body text, meta jsonb default null) returns void
language sql security definer set search_path = public, app as $$
  insert into public.clan_messages (clan_id, user_id, kind, body, meta) values (cid, null, 'system', body, meta)
$$;

create or replace function app.clan_add_member(cid uuid, uid uuid, r public.clan_role) returns void
language plpgsql security definer set search_path = public, app as $$
begin
  insert into public.clan_members (clan_id, user_id, role) values (cid, uid, r);
  update public.clans set member_count = member_count + 1 where id = cid;
  delete from public.clan_join_requests where user_id = uid and status = 'pending';
  insert into public.clan_events (clan_id, actor, type, payload) values (cid, uid, 'joined', '{}');
  perform app.clan_system_message(cid, (select username from public.profiles where id = uid) || ' joined the clan.',
                                  jsonb_build_object('event', 'joined', 'userId', uid));
end $$;

-- Removes a member; their war roster entry keeps reps done so far (left_at, doc 09 §3).
create or replace function app.clan_remove_member(cid uuid, uid uuid, why text) returns void
language plpgsql security definer set search_path = public, app as $$
begin
  delete from public.clan_members where clan_id = cid and user_id = uid;
  if not found then return; end if;
  update public.clans set member_count = greatest(0, member_count - 1) where id = cid;
  update public.clan_war_rosters r set left_at = now() from public.clan_wars w
   where r.war_id = w.id and w.status = 'live' and r.user_id = uid and r.left_at is null;
  insert into public.clan_events (clan_id, actor, type, payload) values (cid, uid, why, '{}');
  perform app.clan_system_message(cid, (select username from public.profiles where id = uid) ||
    case why when 'kicked' then ' was removed from the clan.' else ' left the clan.' end,
    jsonb_build_object('event', why, 'userId', uid));
end $$;

-- ---------------------------------------------------------------------------
-- Clan RPCs
-- ---------------------------------------------------------------------------
create or replace function app.clan_json(cid uuid, viewer uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'badge', c.badge, 'description', c.description,
    'joinPolicy', c.join_policy, 'minTrophies', c.min_trophies, 'country', c.country, 'warEnabled', c.war_enabled,
    'rating', c.rating, 'memberCount', c.member_count, 'maxMembers', 30,
    'myRole', (select role from public.clan_members m where m.clan_id = c.id and m.user_id = viewer),
    'requested', exists (select 1 from public.clan_join_requests r where r.clan_id = c.id and r.user_id = viewer and r.status = 'pending'))
  from public.clans c where c.id = cid
$$;

create or replace function public.create_clan(name text, tag text, badge jsonb default '{}', description text default '',
                                              join_policy text default 'open', min_trophies int default 0,
                                              country text default null) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_id uuid;
begin
  if exists (select 1 from public.clan_members where user_id = me) then
    raise exception 'leave your clan first' using errcode = '22023', hint = 'already_in_clan';
  end if;
  if not exists (select 1 from public.profiles where id = me and onboarding_completed) then
    raise exception 'finish your profile first' using errcode = '22023';
  end if;
  if char_length(trim(name)) not between 3 and 24 or app.has_profanity(name) then
    raise exception 'invalid clan name' using errcode = '22023', hint = 'invalid_name';
  end if;
  if upper(tag) !~ '^[A-Z0-9]{3,5}$' or app.has_profanity(tag) then
    raise exception 'invalid clan tag' using errcode = '22023', hint = 'invalid_tag';
  end if;
  if app.has_profanity(description) then raise exception 'invalid description' using errcode = '22023'; end if;
  perform app.hit_rate_limit(me, 'create_clan', 3, interval '1 day');
  begin
    insert into public.clans (name, tag, badge, description, join_policy, min_trophies, country, created_by)
    values (trim(name), upper(tag), coalesce(badge, '{}'), coalesce(description, ''), join_policy::public.join_policy,
            greatest(coalesce(min_trophies, 0), 0), nullif(upper(country), ''), me)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'name or tag taken' using errcode = '23505', hint = 'taken';
  end;
  perform app.clan_add_member(v_id, me, 'leader');
  return app.clan_json(v_id, me);
end $$;

create or replace function public.update_clan(patch jsonb) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
  k text;
begin
  if app.role_rank(m.role) < 3 then raise exception 'leaders only' using errcode = '42501'; end if;
  for k in select jsonb_object_keys(patch) loop
    if k not in ('badge', 'description', 'joinPolicy', 'minTrophies', 'country', 'warEnabled') then
      raise exception 'field % cannot be changed', k using errcode = '22023';
    end if;
  end loop;
  if app.has_profanity(patch->>'description') then raise exception 'invalid description' using errcode = '22023'; end if;
  update public.clans set
    badge = coalesce(patch->'badge', badge),
    description = coalesce(patch->>'description', description),
    join_policy = coalesce((patch->>'joinPolicy')::public.join_policy, join_policy),
    min_trophies = coalesce(greatest((patch->>'minTrophies')::int, 0), min_trophies),
    country = case when patch ? 'country' then nullif(upper(patch->>'country'), '') else country end,
    war_enabled = coalesce((patch->>'warEnabled')::boolean, war_enabled)
  where id = m.clan_id;
  insert into public.clan_events (clan_id, actor, type, payload) values (m.clan_id, me, 'settings', patch);
  return app.clan_json(m.clan_id, me);
end $$;

-- Join (open), request (request), or refuse (invite_only / full / requirements).
create or replace function public.join_clan(clan_id uuid, message text default null) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  c public.clans;
  p public.profiles;
begin
  if exists (select 1 from public.clan_members m where m.user_id = me) then
    raise exception 'leave your clan first' using errcode = '22023', hint = 'already_in_clan';
  end if;
  select * into c from public.clans where id = join_clan.clan_id for update;
  if not found then raise exception 'clan not found' using errcode = 'P0002'; end if;
  select * into p from public.profiles where id = me;
  if c.member_count >= 30 then raise exception 'clan is full' using errcode = '22023', hint = 'full'; end if;
  if p.trophies < c.min_trophies then raise exception 'not enough trophies' using errcode = '22023', hint = 'requirements'; end if;
  if c.country is not null and p.country is distinct from c.country then
    raise exception 'country requirement' using errcode = '22023', hint = 'requirements';
  end if;
  if c.join_policy = 'invite_only' then raise exception 'invite only' using errcode = '42501', hint = 'invite_only'; end if;
  if c.join_policy = 'request' then
    if app.has_profanity(message) then raise exception 'invalid message' using errcode = '22023'; end if;
    insert into public.clan_join_requests (clan_id, user_id, message) values (c.id, me, left(message, 200))
    on conflict on constraint clan_join_requests_pkey do update set status = 'pending', message = excluded.message, created_at = now();
    perform app.enqueue_push(m.user_id, 'clan_join_request', 'clan',
      jsonb_build_object('username', p.username, 'clanId', c.id), 'clanreq:' || c.id)
      from public.clan_members m where m.clan_id = c.id and m.role in ('leader', 'co_leader');
    return 'requested';
  end if;
  perform app.clan_add_member(c.id, me, 'member');
  return 'joined';
end $$;

create or replace function public.respond_clan_request(user_id uuid, accept boolean) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
begin
  if app.role_rank(m.role) < 2 then raise exception 'elders and up only' using errcode = '42501'; end if;
  update public.clan_join_requests r set status = case when accept then 'accepted' else 'declined' end
   where r.clan_id = m.clan_id and r.user_id = respond_clan_request.user_id and r.status = 'pending';
  if not found then raise exception 'request not found' using errcode = 'P0002'; end if;
  if not accept then return 'declined'; end if;
  if exists (select 1 from public.clan_members x where x.user_id = respond_clan_request.user_id) then
    raise exception 'already in a clan' using errcode = '22023', hint = 'already_in_clan';
  end if;
  if (select member_count from public.clans where id = m.clan_id) >= 30 then
    raise exception 'clan is full' using errcode = '22023', hint = 'full';
  end if;
  perform app.clan_add_member(m.clan_id, respond_clan_request.user_id, 'member');
  return 'joined';
end $$;

create or replace function public.leave_clan() returns text
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
  v_next uuid;
begin
  if m.role = 'leader' then
    select user_id into v_next from public.clan_members
     where clan_id = m.clan_id and user_id <> me order by app.role_rank(role) desc, joined_at limit 1;
    if v_next is null then                                    -- last member: the clan is disbanded
      delete from public.clans where id = m.clan_id;
      return 'disbanded';
    end if;
    perform app.clan_remove_member(m.clan_id, me, 'left');
    update public.clan_members set role = 'leader' where clan_id = m.clan_id and user_id = v_next;
    perform app.clan_system_message(m.clan_id, (select username from public.profiles where id = v_next) || ' is the new leader.');
    return 'left';
  end if;
  perform app.clan_remove_member(m.clan_id, me, 'left');
  return 'left';
end $$;

-- Kick: leader any; co-leader elders + members; elder members (doc 09 §2).
create or replace function public.kick_member(user_id uuid) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
  t public.clan_members;
begin
  select * into t from public.clan_members x where x.clan_id = m.clan_id and x.user_id = kick_member.user_id;
  if not found or t.user_id = me then raise exception 'member not found' using errcode = 'P0002'; end if;
  if app.role_rank(m.role) < 2 or app.role_rank(t.role) >= app.role_rank(m.role) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  perform app.clan_remove_member(m.clan_id, t.user_id, 'kicked');
end $$;

-- Promote / demote: leader up to co-leader (max 3); co-leader up to elder (doc 09 §2).
create or replace function public.set_member_role(user_id uuid, role text) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
  t public.clan_members;
  v_role public.clan_role := role::public.clan_role;
begin
  select * into t from public.clan_members x where x.clan_id = m.clan_id and x.user_id = set_member_role.user_id;
  if not found or t.user_id = me then raise exception 'member not found' using errcode = 'P0002'; end if;
  if v_role = 'leader' then raise exception 'use transfer_leadership' using errcode = '22023'; end if;
  if not ((m.role = 'leader') or (m.role = 'co_leader' and app.role_rank(v_role) <= 2 and app.role_rank(t.role) <= 2)) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if v_role = 'co_leader' and (select count(*) from public.clan_members x where x.clan_id = m.clan_id and x.role = 'co_leader') >= 3 then
    raise exception 'max 3 co-leaders' using errcode = '22023', hint = 'co_leader_limit';
  end if;
  update public.clan_members x set role = v_role where x.clan_id = m.clan_id and x.user_id = t.user_id;
  insert into public.clan_events (clan_id, actor, type, payload)
  values (m.clan_id, me, 'role', jsonb_build_object('userId', t.user_id, 'role', v_role));
  perform app.clan_system_message(m.clan_id, (select username from public.profiles where id = t.user_id) || ' is now ' ||
    replace(v_role::text, '_', '-') || '.', jsonb_build_object('event', 'role', 'userId', t.user_id, 'role', v_role));
end $$;

create or replace function public.transfer_leadership(user_id uuid) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
begin
  if m.role <> 'leader' then raise exception 'leader only' using errcode = '42501'; end if;
  if not exists (select 1 from public.clan_members x where x.clan_id = m.clan_id and x.user_id = transfer_leadership.user_id
                   and x.user_id <> me) then
    raise exception 'member not found' using errcode = 'P0002';
  end if;
  update public.clan_members x set role = 'co_leader' where x.clan_id = m.clan_id and x.user_id = me;
  update public.clan_members x set role = 'leader' where x.clan_id = m.clan_id and x.user_id = transfer_leadership.user_id;
  perform app.clan_system_message(m.clan_id, (select username from public.profiles where id = transfer_leadership.user_id)
                                  || ' is the new leader.');
end $$;

create or replace function public.disband_clan() returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
begin
  if m.role <> 'leader' then raise exception 'leader only' using errcode = '42501'; end if;
  insert into public.clan_events (clan_id, actor, type, payload) values (m.clan_id, me, 'disbanded', '{}');
  delete from public.clans where id = m.clan_id;
end $$;

-- Discovery (doc 09 §4): name / tag search + filters; recommended = has space, similar trophies, my country first.
create or replace function public.search_clans(q text default '', open_only boolean default false, country text default null)
returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_q text := lower(trim(coalesce(q, '')));
  p public.profiles;
begin
  select * into p from public.profiles where id = me;
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((select jsonb_agg(app.clan_json(c.id, me) order by
                     (c.country is not distinct from p.country) desc, abs(c.min_trophies - p.trophies), c.rating desc)
    from (select * from public.clans c
           where (v_q = '' or lower(c.name::text) like '%' || v_q || '%' or lower(c.tag::text) like v_q || '%')
             and (not open_only or c.join_policy = 'open')
             and (search_clans.country is null or c.country = upper(search_clans.country))
             and (v_q <> '' or (c.member_count < 30 and c.join_policy <> 'invite_only' and c.min_trophies <= p.trophies))
           order by (c.country is not distinct from p.country) desc, c.rating desc limit 30) c), '[]'::jsonb);
end $$;

-- Clan home: clan, members (role, trophies, today's reps, this war's counted reps), requests (for elders+).
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
  select id into v_war from public.clan_wars w where w.status = 'live' and v_cid in (w.clan_a, w.clan_b) order by week_start desc limit 1;
  select role into v_role from public.clan_members where user_id = me and clan_members.clan_id = v_cid;
  return app.clan_json(v_cid, me) || jsonb_build_object(
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(m.user_id, me), 'role', m.role,
                  'joinedAt', app.utc_iso(m.joined_at),
                  'repsToday', coalesce((select reps_total from public.user_stats_daily d
                                          where d.user_id = m.user_id and d.day = (now() at time zone 'UTC')::date), 0),
                  'warReps', coalesce((select sum(counted_reps) from public.clan_war_member_daily x
                                        where x.war_id = v_war and x.user_id = m.user_id), 0))
                  order by app.role_rank(m.role) desc, lower(p.username)), '[]')
                  from public.clan_members m join public.profiles p on p.id = m.user_id where m.clan_id = v_cid),
    'requests', case when app.role_rank(coalesce(v_role, 'member')) >= 2 then
                  (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(r.user_id, me), 'message', r.message,
                     'createdAt', app.utc_iso(r.created_at)) order by r.created_at), '[]')
                     from public.clan_join_requests r where r.clan_id = v_cid and r.status = 'pending')
                else '[]'::jsonb end,
    'war', public.get_clan_war(v_cid));
end $$;

-- ---------------------------------------------------------------------------
-- Chat (doc 09 §5): 1 message / 2 s, 200 / day, masked, members only; leaders/co-leaders delete.
-- ---------------------------------------------------------------------------
create or replace function public.send_clan_message(body text, kind text default 'text') returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
  v_id bigint;
  v_body text := trim(coalesce(body, ''));
begin
  if kind not in ('text', 'kudos') then raise exception 'invalid kind' using errcode = '22023'; end if;
  if kind = 'kudos' and v_body not in ('👊', '🔥', '💪') then raise exception 'invalid reaction' using errcode = '22023'; end if;
  if char_length(v_body) not between 1 and 500 then raise exception 'message must be 1–500 characters' using errcode = '22023'; end if;
  perform app.hit_rate_limit(me, 'clan_chat_2s', 1, interval '2 seconds');
  perform app.hit_rate_limit(me, 'clan_chat_day', 200, interval '1 day');
  insert into public.clan_messages (clan_id, user_id, kind, body) values (m.clan_id, me, kind, app.mask_profanity(v_body))
  returning id into v_id;
  -- @mentions notify (doc 15 §2)
  perform app.enqueue_push(p.id, 'clan_mention', 'clan',
    jsonb_build_object('username', (select username from public.profiles where id = me), 'clanId', m.clan_id), 'mention:' || m.clan_id)
    from public.clan_members cm join public.profiles p on p.id = cm.user_id
   where cm.clan_id = m.clan_id and cm.user_id <> me and v_body ~* ('@' || regexp_replace(p.username::text, '([.])', '\\\1', 'g') || '\M');
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.delete_clan_message(message_id bigint) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
begin
  update public.clan_messages x set deleted_at = now()
   where x.id = message_id and x.clan_id = m.clan_id
     and (x.user_id = me or app.role_rank(m.role) >= 3);
  if not found then raise exception 'message not found' using errcode = 'P0002'; end if;
end $$;

create or replace function public.get_clan_messages(before_id bigint default null, lim int default 50) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  m public.clan_members := app.my_membership(me);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'body', x.body, 'meta', x.meta,
            'user', case when x.user_id is null then null else jsonb_build_object('id', x.user_id, 'username', p.username,
                                                                                    'avatarPreset', p.avatar_preset) end,
            'createdAt', app.utc_iso(x.created_at)) order by x.id)
    from (select * from public.clan_messages c where c.clan_id = m.clan_id and c.deleted_at is null
            and (before_id is null or c.id < before_id) order by c.id desc limit least(greatest(lim, 1), 100)) x
    left join public.profiles p on p.id = x.user_id), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Clan Wars (doc 09 §3)
-- ---------------------------------------------------------------------------
create or replace function app.war_week_start(at_ts timestamptz default now()) returns date
language sql immutable as $$ select (date_trunc('week', at_ts at time zone 'UTC'))::date $$;

-- Counts a member's verified reps of one UTC day for their live war (trigger on user_stats_daily).
create or replace function app.on_stats_daily_war() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  r record;
  v_trust int;
  v_counted int;
  v_total bigint;
begin
  select trust_score into v_trust from public.profiles where id = new.user_id;
  for r in select ro.war_id, ro.clan_id, w.clan_a, w.clan_b from public.clan_war_rosters ro join public.clan_wars w on w.id = ro.war_id
            where ro.user_id = new.user_id and ro.left_at is null and w.status = 'live' and w.week_start = app.war_week_start(new.day::timestamp at time zone 'UTC')
  loop
    v_counted := case when v_trust < 30 then 0 else app.clan_war_day_total(new.reps_total, v_trust < 50) end;
    insert into public.clan_war_member_daily as d (war_id, user_id, day, raw_reps, counted_reps)
    values (r.war_id, new.user_id, new.day, new.reps_total, v_counted)
    on conflict (war_id, user_id, day) do update set raw_reps = excluded.raw_reps, counted_reps = excluded.counted_reps;
    select coalesce(sum(d.counted_reps), 0) into v_total from public.clan_war_member_daily d
      join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
     where d.war_id = r.war_id and ro.clan_id = r.clan_id;
    if r.clan_id = r.clan_a then
      update public.clan_wars set score_a = v_total, score_a_at = case when score_a <> v_total then now() else score_a_at end where id = r.war_id;
    else
      update public.clan_wars set score_b = v_total, score_b_at = case when score_b <> v_total then now() else score_b_at end where id = r.war_id;
    end if;
  end loop;
  return new;
end $$;
create trigger user_stats_daily_war after insert or update of reps_total on public.user_stats_daily
  for each row execute function app.on_stats_daily_war();

-- Monday 00:00 UTC: pair eligible clans (≥ 5 members, war on, at Sunday 23:00) by active members (±20 %) then rating.
create or replace function app.clan_war_matchmake(week date default app.war_week_start()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  c record;
  o record;
  v_id uuid;
  v_n int := 0;
begin
  create temp table if not exists tmp_war_pool (clan_id uuid primary key, active int, rating int, last_opp uuid, taken boolean)
    on commit drop;
  delete from tmp_war_pool;
  insert into tmp_war_pool
  select cl.id,
         (select count(distinct m.user_id) from public.clan_members m join public.rep_sessions s on s.user_id = m.user_id
           where m.clan_id = cl.id and s.verified and s.started_at >= week::timestamp at time zone 'UTC' - interval '7 days'),
         cl.rating,
         (select case when w.clan_a = cl.id then w.clan_b else w.clan_a end from public.clan_wars w
           where w.week_start = week - 7 and cl.id in (w.clan_a, w.clan_b) limit 1),
         false
    from public.clans cl
   where cl.war_enabled and cl.member_count >= 5
     and not exists (select 1 from public.clan_wars w where w.week_start = week and cl.id in (w.clan_a, w.clan_b));
  for c in select * from tmp_war_pool order by active desc, rating desc loop
    continue when (select taken from tmp_war_pool where clan_id = c.clan_id);
    select * into o from tmp_war_pool x
     where not x.taken and x.clan_id <> c.clan_id and x.clan_id is distinct from c.last_opp
       and x.active between floor(c.active * 0.8) and ceil(c.active * 1.2)
     order by abs(x.rating - c.rating), x.clan_id limit 1;
    if not found then        -- no clan of similar size: closest rating among the rest
      select * into o from tmp_war_pool x
       where not x.taken and x.clan_id <> c.clan_id and x.clan_id is distinct from c.last_opp
       order by abs(x.active - c.active), abs(x.rating - c.rating), x.clan_id limit 1;
    end if;
    update tmp_war_pool set taken = true where clan_id in (c.clan_id, o.clan_id);
    insert into public.clan_wars (week_start, clan_a, clan_b, status) values (week, c.clan_id, o.clan_id, 'live')
    returning id into v_id;
    insert into public.clan_war_rosters (war_id, clan_id, user_id)
    select v_id, m.clan_id, m.user_id from public.clan_members m where m.clan_id in (c.clan_id, o.clan_id);
    v_n := v_n + 1;
    perform app.clan_system_message(x, 'The Clan War has started!', jsonb_build_object('event', 'war_started', 'warId', v_id))
      from unnest(array[c.clan_id, o.clan_id]) x where x is not null;
  end loop;
  return v_n;
end $$;

-- Finishes a week: winner, tie-breaks, Elo (K = 32, no change for byes), MVPs and chest tiers (doc 09 §3).
create or replace function app.clan_war_finalize(week date) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  w public.clan_wars;
  v_winner uuid;
  v_reason text;
  v_c50_a int;
  v_c50_b int;
  ra int;
  rb int;
  ea double precision;
  sa double precision;
  v_n int := 0;
begin
  for w in select * from public.clan_wars where week_start = week and status = 'live' for update loop
    if w.clan_b is null then
      v_winner := w.clan_a;
      v_reason := 'bye';
    else
      select count(*) filter (where ro.clan_id = w.clan_a and t >= 50), count(*) filter (where ro.clan_id = w.clan_b and t >= 50)
        into v_c50_a, v_c50_b
        from (select d.user_id, sum(d.counted_reps) t from public.clan_war_member_daily d where d.war_id = w.id group by 1) s
        join public.clan_war_rosters ro on ro.war_id = w.id and ro.user_id = s.user_id;
      if w.score_a <> w.score_b then
        v_winner := case when w.score_a > w.score_b then w.clan_a else w.clan_b end;
        v_reason := 'score';
      elsif v_c50_a <> v_c50_b then
        v_winner := case when v_c50_a > v_c50_b then w.clan_a else w.clan_b end;
        v_reason := 'contributors';
      elsif w.score_a > 0 and w.score_a_at is distinct from w.score_b_at then
        v_winner := case when coalesce(w.score_a_at, 'infinity') < coalesce(w.score_b_at, 'infinity') then w.clan_a else w.clan_b end;
        v_reason := 'earlier';
      else
        v_winner := null;
        v_reason := 'draw';
      end if;
      select rating into ra from public.clans where id = w.clan_a;
      select rating into rb from public.clans where id = w.clan_b;
      ea := 1 / (1 + power(10, (rb - ra) / 400.0));
      sa := case when v_winner = w.clan_a then 1 when v_winner = w.clan_b then 0 else 0.5 end;
      update public.clans set rating = ra + round(32 * (sa - ea))::int where id = w.clan_a;
      update public.clans set rating = rb + round(32 * ((1 - sa) - (1 - ea)))::int where id = w.clan_b;
    end if;
    update public.clan_wars set status = 'finished', finished_at = now(), winner = v_winner,
      result = jsonb_build_object('reason', v_reason,
        'mvp', jsonb_build_object(
          'a', (select d.user_id from public.clan_war_member_daily d join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
                 where d.war_id = w.id and ro.clan_id = w.clan_a group by d.user_id order by sum(d.counted_reps) desc, d.user_id limit 1),
          'b', (select d.user_id from public.clan_war_member_daily d join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
                 where d.war_id = w.id and ro.clan_id = w.clan_b group by d.user_id order by sum(d.counted_reps) desc, d.user_id limit 1)),
        'chests', (select coalesce(jsonb_agg(jsonb_build_object('userId', s.user_id, 'tier',
                     case when w.clan_b is null then 'bronze' when ro.clan_id = v_winner then 'gold' else 'silver' end)), '[]')
                     from (select d.user_id, sum(d.counted_reps) t from public.clan_war_member_daily d where d.war_id = w.id group by 1) s
                     join public.clan_war_rosters ro on ro.war_id = w.id and ro.user_id = s.user_id where s.t >= 50))
     where id = w.id;
    perform app.clan_system_message(x, case when v_winner is null then 'The Clan War ended in a draw.'
                                            when v_winner = x then 'We won the Clan War! 🏆' else 'We lost the Clan War. Next week!' end,
                                    jsonb_build_object('event', 'war_ended', 'warId', w.id))
      from unnest(array[w.clan_a, w.clan_b]) x where x is not null;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

create or replace function app.clan_war_rollover(now_at timestamptz default now()) returns void
language plpgsql security definer set search_path = public, app as $$
begin
  perform app.clan_war_finalize(w.week_start) from (select distinct week_start from public.clan_wars
                                                    where status = 'live' and week_start < app.war_week_start(now_at)) w;
  perform app.clan_war_matchmake(app.war_week_start(now_at));
end $$;

-- War card for a clan (doc 09 §4): opponent, scores, time left, my contribution today with the cap.
create or replace function public.get_clan_war(clan_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := coalesce(clan_id, app.my_clan_id(me));
  w public.clan_wars;
  v_mine boolean;
  v_today int;
begin
  if v_cid is null then return null; end if;
  select * into w from public.clan_wars x where v_cid in (x.clan_a, x.clan_b) order by x.week_start desc limit 1;
  if not found then return null; end if;
  v_mine := v_cid = w.clan_a;
  select coalesce(sum(d.raw_reps), 0) into v_today from public.clan_war_member_daily d
   where d.war_id = w.id and d.user_id = me and d.day = (now() at time zone 'UTC')::date;
  return jsonb_build_object('id', w.id, 'status', w.status, 'weekStart', w.week_start,
    'endsAt', app.utc_iso((w.week_start + 7)::timestamp at time zone 'UTC'),
    'opponent', case when (case when v_mine then w.clan_b else w.clan_a end) is null then null
                     else app.clan_json(case when v_mine then w.clan_b else w.clan_a end, me) end,
    'score', jsonb_build_object('us', case when v_mine then w.score_a else w.score_b end,
                                'them', case when v_mine then w.score_b else w.score_a end),
    'result', case when w.status = 'finished' then w.result || jsonb_build_object('won', w.winner = v_cid, 'draw', w.winner is null) end,
    'myToday', jsonb_build_object('raw', v_today, 'counted', app.clan_war_day_total(v_today, false), 'fullCap', 200, 'halfCap', 400),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(s.user_id, me), 'reps', s.t) order by s.t desc), '[]')
              from (select d.user_id, sum(d.counted_reps) t from public.clan_war_member_daily d
                      join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
                     where d.war_id = w.id and ro.clan_id = v_cid group by 1 order by 2 desc limit 5) s));
end $$;

-- Clans board (doc 08 §4): by rating, or by this week's war score. Small table → computed live.
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
                                            else coalesce((select case when w.clan_a = c.id then w.score_a else w.score_b end
                                                             from public.clan_wars w where w.week_start = app.war_week_start()
                                                              and c.id in (w.clan_a, w.clan_b)), 0) end score) s
           where get_clan_leaderboard.country is null or c.country = upper(get_clan_leaderboard.country)
           order by s.score desc limit 100) r);
end $$;

-- Leader inactive 14 days → most active co-leader / elder / member by last-14-day verified reps (doc 09 §2).
create or replace function app.clan_auto_transfer(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  l record;
  v_next uuid;
  v_n int := 0;
begin
  for l in select m.clan_id, m.user_id from public.clan_members m where m.role = 'leader'
             and not exists (select 1 from public.rep_sessions s where s.user_id = m.user_id and s.started_at > now_at - interval '14 days')
             and m.joined_at < now_at - interval '14 days' loop
    select m.user_id into v_next from public.clan_members m
     where m.clan_id = l.clan_id and m.user_id <> l.user_id
       and exists (select 1 from public.rep_sessions s where s.user_id = m.user_id and s.started_at > now_at - interval '14 days')
     order by app.role_rank(m.role) desc,
              (select coalesce(sum(s.reps_counted), 0) from public.rep_sessions s
                where s.user_id = m.user_id and s.verified and s.started_at > now_at - interval '14 days') desc
     limit 1;
    continue when v_next is null;
    update public.clan_members set role = 'co_leader' where clan_id = l.clan_id and user_id = l.user_id;
    update public.clan_members set role = 'leader' where clan_id = l.clan_id and user_id = v_next;
    perform app.clan_system_message(l.clan_id, (select username from public.profiles where id = v_next) ||
                                    ' is the new leader (the previous leader was inactive for 14 days).');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Clan tag next to usernames (doc 09 §1): user cards gain "clanTag".
create or replace function app.user_card(uid uuid, viewer uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'avatarPreset', p.avatar_preset,
    'country', p.country, 'level', p.level, 'trophies', p.trophies,
    'clanTag', (select c.tag::text from public.clan_members m join public.clans c on c.id = m.clan_id where m.user_id = p.id),
    'streak', case when p.profile_visibility = 'public' or p.id = viewer
                     or (p.profile_visibility = 'friends' and app.are_friends(p.id, viewer))
                   then coalesce((select current from public.streaks s where s.user_id = p.id), 0) end)
  from public.profiles p where p.id = uid
$$;

do $$
declare f text;
begin
  foreach f in array array['create_clan(text, text, jsonb, text, text, int, text)', 'update_clan(jsonb)', 'join_clan(uuid, text)',
                           'respond_clan_request(uuid, boolean)', 'leave_clan()', 'kick_member(uuid)', 'set_member_role(uuid, text)',
                           'transfer_leadership(uuid)', 'disband_clan()', 'search_clans(text, boolean, text)', 'get_clan(uuid)',
                           'send_clan_message(text, text)', 'delete_clan_message(bigint)', 'get_clan_messages(bigint, int)',
                           'get_clan_war(uuid)', 'get_clan_leaderboard(text, text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
grant execute on all functions in schema app to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then return; end if;
  perform cron.schedule('pushly-clan-wars', '0 0 * * 1', 'select app.clan_war_rollover()');
  perform cron.schedule('pushly-clan-leaders', '30 3 * * *', 'select app.clan_auto_transfer()');
end $$;
