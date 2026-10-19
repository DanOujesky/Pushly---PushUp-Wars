-- 0002 — profiles & devices (doc 11 §2, roadmap P1-03)

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username citext unique not null check (username ~ '^[A-Za-z0-9_.]{3,20}$'),
  username_changed_at timestamptz,
  onboarding_completed boolean not null default false,
  avatar_preset text, avatar_path text,
  country char(2) check (country ~ '^[A-Z]{2}$'),
  birth_year smallint check (birth_year between 1900 and 2100),
  timezone text not null default 'UTC',
  profile_visibility public.visibility_t not null default 'public',
  leaderboard_visible boolean not null default true,
  trophies int not null default 0 check (trophies >= 0),
  trophy_floor int not null default 0,
  placement_battles_left smallint not null default 5,
  mmr double precision not null default 1500,
  mmr_rd double precision not null default 350,
  mmr_vol double precision not null default 0.06,
  trust_score smallint not null default 70 check (trust_score between 0 and 100),
  xp int not null default 0,
  level smallint not null default 1,
  is_pro boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_touch before update on public.profiles
  for each row execute function app.touch_updated_at();

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform public.platform_t not null,
  model text, os_version text, app_version text,
  attest_key_id text, public_key text,
  attested_at timestamptz,
  push_token text, push_token_updated_at timestamptz,
  last_seen_at timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index devices_user_id_idx on public.devices(user_id);

-- ---------------------------------------------------------------------------
-- Signup: every auth user gets a profile with a placeholder username.
-- The client finishes onboarding via update_profile() (doc 02 PS-03).
-- ---------------------------------------------------------------------------
create or replace function app.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  candidate text := 'u_' || right(replace(new.id::text, '-', ''), 12);
begin
  -- Placeholder must be unique; on the (rare) collision fall back to random suffixes.
  for attempt in 1..5 loop
    begin
      insert into public.profiles (id, username) values (new.id, candidate);
      return new;
    exception when unique_violation then
      -- md5 (core Postgres) instead of pgcrypto: on Supabase, pgcrypto lives in schema `extensions`
      candidate := 'u_' || substr(md5(random()::text || clock_timestamp()::text), 1, 12);
    end;
  end loop;
  raise exception 'could not allocate placeholder username';
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function app.handle_new_user();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.devices  enable row level security;

-- Clients never write these tables directly (CLAUDE.md §4.2): writes go through RPCs / Edge Functions.
revoke insert, update, delete on public.profiles from anon, authenticated;
revoke insert, update, delete on public.devices  from anon, authenticated;
revoke all on public.profiles, public.devices from anon;

create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());

create policy devices_select_own on public.devices
  for select to authenticated using (user_id = auth.uid());

-- Public, column-limited view of other users (doc 11 §9).
create view public.public_profiles
with (security_barrier = true) as
  select p.id, p.username, p.avatar_preset, p.avatar_path, p.country,
         p.trophies, p.level, p.is_pro, p.profile_visibility, p.created_at
  from public.profiles p
  where p.onboarding_completed;

revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- update_profile(patch) — the only way a user edits their profile.
-- Whitelisted keys: username, avatar_preset, avatar_path, country, birth_year,
-- timezone, profile_visibility, leaderboard_visible.
-- ---------------------------------------------------------------------------
create or replace function public.update_profile(patch jsonb) returns public.profiles
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := auth.uid();
  allowed text[] := array['username','avatar_preset','avatar_path','country','birth_year',
                          'timezone','profile_visibility','leaderboard_visible'];
  k text;
  cur public.profiles;
  new_username citext;
  new_birth_year int;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if patch is null or jsonb_typeof(patch) <> 'object' then
    raise exception 'patch must be a JSON object' using errcode = '22023';
  end if;

  for k in select jsonb_object_keys(patch) loop
    if not k = any(allowed) then
      raise exception 'field % cannot be updated', k using errcode = '22023';
    end if;
  end loop;

  select * into cur from public.profiles where id = uid for update;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;

  if patch ? 'username' then
    new_username := patch->>'username';
    if new_username is distinct from cur.username then
      if new_username !~ '^[A-Za-z0-9_.]{3,20}$' then
        raise exception 'invalid username' using errcode = '22023';
      end if;
      if new_username::text ~ '^u_[0-9a-f]{12}$' then
        raise exception 'username is reserved' using errcode = '22023';
      end if;
      -- first change (from placeholder during onboarding) is free; later max 1 per 30 days
      if cur.onboarding_completed and cur.username_changed_at is not null
         and cur.username_changed_at > now() - interval '30 days' then
        raise exception 'username can be changed once per 30 days' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.profiles where username = new_username and id <> uid) then
        raise exception 'username taken' using errcode = '23505';
      end if;
      cur.username := new_username;
      cur.username_changed_at := now();
    end if;
  end if;

  if patch ? 'birth_year' then
    new_birth_year := (patch->>'birth_year')::int;
    -- Age gate 16+ by birth year (doc 16 §2)
    if new_birth_year is null or extract(year from now())::int - new_birth_year < 16
       or new_birth_year < 1900 then
      raise exception 'minimum age is 16' using errcode = '22023';
    end if;
    cur.birth_year := new_birth_year;
  end if;

  if patch ? 'country' then
    cur.country := nullif(upper(patch->>'country'), '');
  end if;

  if patch ? 'timezone' then
    if not exists (select 1 from pg_timezone_names where name = patch->>'timezone') then
      raise exception 'unknown timezone' using errcode = '22023';
    end if;
    cur.timezone := patch->>'timezone';
  end if;

  if patch ? 'avatar_preset' then cur.avatar_preset := patch->>'avatar_preset'; end if;
  if patch ? 'avatar_path' then
    if patch->>'avatar_path' is not null and patch->>'avatar_path' not like uid::text || '/%' then
      raise exception 'avatar must be in your own folder' using errcode = '42501';
    end if;
    cur.avatar_path := patch->>'avatar_path';
  end if;
  if patch ? 'profile_visibility' then cur.profile_visibility := (patch->>'profile_visibility')::public.visibility_t; end if;
  if patch ? 'leaderboard_visible' then cur.leaderboard_visible := (patch->>'leaderboard_visible')::boolean; end if;

  -- Onboarding completes once a real username and birth year are set.
  cur.onboarding_completed := cur.onboarding_completed
    or (cur.birth_year is not null and cur.username::text !~ '^u_[0-9a-f]{12}$');

  update public.profiles set
    username = cur.username, username_changed_at = cur.username_changed_at,
    avatar_preset = cur.avatar_preset, avatar_path = cur.avatar_path,
    country = cur.country, birth_year = cur.birth_year, timezone = cur.timezone,
    profile_visibility = cur.profile_visibility, leaderboard_visible = cur.leaderboard_visible,
    onboarding_completed = cur.onboarding_completed
  where id = uid
  returning * into cur;

  return cur;
end $$;

revoke all on function public.update_profile(jsonb) from public, anon;
grant execute on function public.update_profile(jsonb) to authenticated;

-- username_available(name) — used by onboarding for live availability check
create or replace function public.username_available(name text) returns boolean
language sql stable security definer set search_path = public as $$
  select name ~ '^[A-Za-z0-9_.]{3,20}$'
     and name !~ '^u_[0-9a-f]{12}$'
     and not exists (select 1 from public.profiles where username = name::citext and id <> auth.uid())
$$;

revoke all on function public.username_available(text) from public, anon;
grant execute on function public.username_available(text) to authenticated;
