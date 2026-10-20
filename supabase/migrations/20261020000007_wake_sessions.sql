-- 0007 — wake attempts, streaks, rep sessions, stats (doc 11 §4–5) + the server's Wake Challenge rules
-- (doc 04 §3/§7, doc 08 §3, roadmap P4-01/P4-03).
--
-- The rules are a 1:1 port of tools/reference/pushly_ref/wake.py and are tested against the shared vectors
-- (supabase/tests/041_wake_vectors.sql is generated from shared/test-vectors/wake). Clients never write any table
-- here: the Edge Function `submit-rep-session` validates a rep log and calls `apply_validated_session` (service role).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.wake_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  local_date date not null,
  occurrence_id text,                               -- null for paused / skipped days
  alarm_id uuid references public.alarm_schedules(id) on delete set null,
  alarm_version int,
  scheduled_at timestamptz, deadline_at timestamptz,
  mode jsonb,                                       -- snapshot of the mode config
  status public.wake_status not null,
  reason text,
  session_id uuid,                                  -- deciding rep session
  final_target_reps smallint, snoozes_used smallint not null default 0,
  score int,                                        -- reps (sprint: reps in the window, sets: sets done)
  points smallint not null default 0,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, local_date)
);
create trigger wake_attempts_touch before update on public.wake_attempts
  for each row execute function app.touch_updated_at();

create table public.streaks (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  current int not null default 0, best int not null default 0,           -- personal streak (freezes allowed)
  pure_current int not null default 0, pure_best int not null default 0,  -- leaderboard streak (no freezes, D-014)
  last_counted_date date,
  freezes_available smallint not null default 0 check (freezes_available between 0 and 2),
  settled_through date,                             -- last local date whose wake result is final (settle job)
  updated_at timestamptz not null default now()
);

create table public.streak_freeze_grants (           -- freezes earned (achievements, Pro, rewarded ad — later phases)
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  granted_on date not null,                         -- user's local date
  count smallint not null default 1 check (count between 1 and 2),
  source text not null,
  created_at timestamptz not null default now()
);
create index streak_freeze_grants_user_idx on public.streak_freeze_grants(user_id, granted_on);

create table public.rep_sessions (
  id uuid primary key,                              -- sessionId from the client (idempotency key)
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid references public.devices(id) on delete set null,
  context public.session_context not null,
  occurrence_id text, battle_id uuid, round_index smallint,
  started_at timestamptz not null, ended_at timestamptz not null,
  reps_counted int not null check (reps_counted >= 0),
  best_set int not null default 0,
  avg_quality smallint,
  rejected jsonb not null default '{}',
  spec_version smallint not null, app_version text not null, platform public.platform_t,
  verified boolean not null default false,
  verification jsonb not null default '{}',         -- per-check results, suspicion scores
  result jsonb,                                     -- the response returned to the client (idempotent replay)
  late boolean not null default false,
  received_at timestamptz not null default now()
);
create index rep_sessions_user_started_idx on public.rep_sessions(user_id, started_at desc);
create index rep_sessions_battle_idx on public.rep_sessions(battle_id) where battle_id is not null;

create table public.rep_session_logs (                -- raw signed logs, retention 90 days (cron purge, later)
  session_id uuid primary key references public.rep_sessions(id) on delete cascade,
  log jsonb not null,
  signature text not null unique,
  created_at timestamptz not null default now()
);

-- Competitive aggregates (UTC periods, CLAUDE.md §6)
create table public.user_stats_daily (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  reps_total int not null default 0, reps_wake int not null default 0,
  reps_battle int not null default 0, reps_training int not null default 0,
  wake_points int not null default 0, sessions int not null default 0,
  primary key (user_id, day)
);
create table public.user_stats_weekly (
  user_id uuid not null references public.profiles(id) on delete cascade,
  week_start date not null, reps_total int not null default 0, wake_points int not null default 0,
  primary key (user_id, week_start)
);
create table public.user_stats_monthly (
  user_id uuid not null references public.profiles(id) on delete cascade,
  month date not null, reps_total int not null default 0, wake_points int not null default 0,
  primary key (user_id, month)
);
create table public.user_stats_alltime (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  reps_total bigint not null default 0, wake_points bigint not null default 0, best_set int not null default 0
);
create index user_stats_daily_board_idx on public.user_stats_daily(day, reps_total desc);
create index user_stats_weekly_reps_idx on public.user_stats_weekly(week_start, reps_total desc);
create index user_stats_weekly_wake_idx on public.user_stats_weekly(week_start, wake_points desc);
create index user_stats_monthly_reps_idx on public.user_stats_monthly(month, reps_total desc);
create index user_stats_monthly_wake_idx on public.user_stats_monthly(month, wake_points desc);
create index user_stats_alltime_reps_idx on public.user_stats_alltime(reps_total desc);

-- Personal aggregates (user's local day)
create table public.user_stats_local_daily (
  user_id uuid not null references public.profiles(id) on delete cascade,
  local_date date not null,
  reps_total int not null default 0, reps_wake int not null default 0, reps_battle int not null default 0,
  reps_training int not null default 0, best_set int not null default 0, avg_quality smallint,
  sessions int not null default 0,
  primary key (user_id, local_date)
);

create table public.personal_records (
  user_id uuid not null references public.profiles(id) on delete cascade,
  record text not null,                             -- 'best_set', 'max_day', ...
  value int not null, session_id uuid, achieved_at timestamptz not null,
  primary key (user_id, record)
);

create table public.anti_cheat_flags (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid, battle_id uuid,
  type text not null, severity public.flag_severity not null, details jsonb,
  status public.flag_status not null default 'open',
  trust_delta smallint not null default 0,
  created_at timestamptz not null default now(), resolved_by uuid, resolved_at timestamptz
);
create index anti_cheat_flags_user_idx on public.anti_cheat_flags(user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- RLS (doc 11 §9): own rows readable; nothing writable by clients.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['wake_attempts','streaks','streak_freeze_grants','rep_sessions','rep_session_logs',
    'user_stats_daily','user_stats_weekly','user_stats_monthly','user_stats_alltime','user_stats_local_daily',
    'personal_records','anti_cheat_flags'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
  end loop;
  foreach t in array array['wake_attempts','streaks','streak_freeze_grants','rep_sessions','user_stats_daily',
    'user_stats_weekly','user_stats_monthly','user_stats_alltime','user_stats_local_daily','personal_records'] loop
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid())',
                   t || '_select_own', t);
  end loop;
  -- rep_session_logs, anti_cheat_flags: service role only (no policy for authenticated).
  revoke select on public.rep_session_logs, public.anti_cheat_flags from authenticated;
end $$;

-- ---------------------------------------------------------------------------
-- Time helpers (mirror of pushly_ref/occurrences.py)
-- ---------------------------------------------------------------------------
-- Local wall-clock date + time → instant. DST gap → first valid minute after the gap; overlap → earlier instance.
create or replace function app.resolve_local(d date, t time, tz text) returns timestamptz
language plpgsql stable as $$
declare
  cand timestamp;
  base timestamptz;
  best timestamptz;
begin
  for m in 0..180 loop
    cand := (d + t) + make_interval(mins => m);
    base := cand at time zone tz;
    select min(x) into best
      from generate_series(base - interval '2 hours', base + interval '2 hours', interval '15 minutes') x
     where (x at time zone tz) = cand;
    if best is not null then return best; end if;
  end loop;
  raise exception 'could not resolve % % in %', d, t, tz;
end $$;

create or replace function app.utc_iso(ts timestamptz) returns text
language sql immutable as $$ select to_char(ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') $$;

create or replace function app.weekday_key(d date) returns text
language sql immutable as $$
  select (array['mon','tue','wed','thu','fri','sat','sun'])[extract(isodow from d)::int]
$$;

-- Which wall-clock time the alarm rings on local date d (enabled, pause, override, weekly / one-off).
create or replace function app.alarm_local_time(s jsonb, d date) returns time
language plpgsql immutable as $$
declare ov jsonb;
begin
  if s is null or not coalesce((s->>'enabled')::boolean, false) then return null; end if;
  if jsonb_typeof(s->'pause') = 'object' and d between (s->'pause'->>'from')::date and (s->'pause'->>'to')::date then
    return null;
  end if;
  if s->>'kind' = 'oneOff' then
    return case when (s->>'oneOff')::timestamp::date = d then (s->>'oneOff')::timestamp::time end;
  end if;
  for ov in select * from jsonb_array_elements(coalesce(s->'overrides', '[]')) loop
    if ov->>'date' = d::text then
      if coalesce((ov->>'skip')::boolean, false) then return null; end if;
      return (ov->>'time')::time;
    end if;
  end loop;
  return nullif(s->'weekly'->>app.weekday_key(d), '')::time;
end $$;

-- Nominal ring time ignoring enabled / pause / skip (only used to pick the snapshot).
create or replace function app.alarm_nominal_time(s jsonb, d date) returns time
language plpgsql immutable as $$
declare ov jsonb;
begin
  if s is null then return null; end if;
  if s->>'kind' = 'oneOff' then
    return case when (s->>'oneOff')::timestamp::date = d then (s->>'oneOff')::timestamp::time end;
  end if;
  for ov in select * from jsonb_array_elements(coalesce(s->'overrides', '[]')) loop
    if ov->>'date' = d::text and not coalesce((ov->>'skip')::boolean, false) and ov->>'time' is not null then
      return (ov->>'time')::time;
    end if;
  end loop;
  return nullif(s->'weekly'->>app.weekday_key(d), '')::time;
end $$;

create or replace function app.alarm_classify(s jsonb, d date) returns text
language plpgsql immutable as $$
declare ov jsonb;
begin
  if s is null or not coalesce((s->>'enabled')::boolean, false)
     or not coalesce((s->>'countsForChallenge')::boolean, false) then
    return 'none';
  end if;
  if jsonb_typeof(s->'pause') = 'object' and d between (s->'pause'->>'from')::date and (s->'pause'->>'to')::date then
    return 'paused';
  end if;
  if s->>'kind' = 'weekly' then
    for ov in select * from jsonb_array_elements(coalesce(s->'overrides', '[]')) loop
      if ov->>'date' = d::text and coalesce((ov->>'skip')::boolean, false) then return 'skipped'; end if;
    end loop;
  end if;
  return case when app.alarm_local_time(s, d) is not null then 'ring' else 'none' end;
end $$;

-- Snapshot rule (PS-26): walking the version timeline forward, a version locks the day at
-- max(validFrom, its nominal ring − 15 min) if it is still current then; first lock wins.
create or replace function app.alarm_snapshot(versions jsonb, d date, tz text) returns jsonb
language plpgsql stable as $$
declare
  arr jsonb[];
  v jsonb;
  t time;
  start_at timestamptz;
  end_at timestamptz;
  lock_at timestamptz;
begin
  select array_agg(x order by (x->>'validFrom')::timestamptz, (x->>'version')::int) into arr
    from jsonb_array_elements(versions) x;
  if arr is null then return null; end if;
  for i in 1..array_length(arr, 1) loop
    v := arr[i];
    start_at := (v->>'validFrom')::timestamptz;
    end_at := case when i < array_length(arr, 1) then (arr[i + 1]->>'validFrom')::timestamptz end;
    t := case when jsonb_typeof(v->'data') = 'object' then app.alarm_nominal_time(v->'data', d) end;
    lock_at := greatest(start_at, app.resolve_local(d, coalesce(t, '00:00'::time), tz) - interval '15 minutes');
    if end_at is null or lock_at < end_at then return v; end if;
  end loop;
  return null;
end $$;

-- Day plan from version histories {alarmId: [{version, validFrom, data}]} — vector-testable core.
create or replace function app.day_plan_from(alarms jsonb, d date, tz text) returns jsonb
language plpgsql stable as $$
declare
  a record;
  v jsonb;
  data jsonb;
  kind text;
  t0 timestamptz;
  best_t0 timestamptz;
  best_id text;
  best_v jsonb;
  kinds text[] := '{}';
begin
  for a in select key, value from jsonb_each(alarms) order by key loop
    v := app.alarm_snapshot(a.value, d, tz);
    data := case when v is not null and jsonb_typeof(v->'data') = 'object' then v->'data' end;
    kind := app.alarm_classify(data, d);
    kinds := kinds || kind;
    if kind = 'ring' then
      t0 := app.resolve_local(d, app.alarm_local_time(data, d), tz);
      if best_t0 is null or t0 < best_t0 or (t0 = best_t0 and a.key < best_id) then
        best_t0 := t0; best_id := a.key; best_v := v;
      end if;
    end if;
  end loop;
  if best_t0 is not null then
    return jsonb_build_object('kind', 'ring', 'alarmId', best_id, 'version', (best_v->>'version')::int,
      'occurrenceId', best_id || ':' || d::text, 't0', app.utc_iso(best_t0),
      'deadline', app.utc_iso(best_t0 + interval '30 minutes'), 'mode', best_v->'data'->'mode');
  end if;
  if 'paused' = any(kinds) then return '{"kind":"paused"}'; end if;
  if 'skipped' = any(kinds) then return '{"kind":"skipped"}'; end if;
  return '{"kind":"none"}';
end $$;

create or replace function app.day_plan(uid uuid, d date, tz text) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select app.day_plan_from(coalesce((
    select jsonb_object_agg(alarm_id, versions) from (
      select alarm_id::text, jsonb_agg(jsonb_build_object('version', version, 'validFrom', valid_from, 'data', data))
             as versions
        from public.alarm_schedule_versions where user_id = uid group by alarm_id) h), '{}'), d, tz)
$$;

-- ---------------------------------------------------------------------------
-- Decision, points, streak (mirror of pushly_ref/wake.py)
-- ---------------------------------------------------------------------------
create or replace function app.wake_final_target(mode jsonb, snoozes int) returns int
language sql immutable as $$
  select case mode->>'type'
    when 'sprint' then (mode->>'minimumReps')::int
    when 'sets' then (mode->>'sets')::int * (mode->>'repsPerSet')::int
    when 'escalation' then (mode->>'targetReps')::int
                           + least(snoozes, (mode->>'maxSnoozes')::int) * (mode->>'snoozeAddsReps')::int
    else (mode->>'targetReps')::int end
$$;

create or replace function app.wake_points(final_target_reps int, mode_type text, snoozes_used int, avg_quality int)
returns int language sql immutable as $$
  select greatest(5, 10 + least(20, final_target_reps / 5)
    + case when mode_type in ('beatTheClock','sprint','sets') then 3
           when mode_type = 'escalation' then -2 * snoozes_used else 0 end
    + case when avg_quality >= 90 then 3 when avg_quality >= 75 then 1 else 0 end)
$$;

-- session (server-time epoch ms): {startedAt, endedAt, ringAt, outcome, snoozes, reps:[{tStart,tEnd,quality}],
-- sets:[{start,end}], sprintStart}. Returns {status, finalTargetReps, successAt, score, reason, snoozesUsed}.
create or replace function app.decide_wake(mode jsonb, t0 bigint, now_ms bigint, s jsonb) returns jsonb
language plpgsql immutable as $$
declare
  deadline bigint := t0 + 30 * 60000;
  mtype text := mode->>'type';
  snoozes int := case when mode->>'type' = 'escalation'
                      then least(coalesce((s->>'snoozes')::int, 0), (mode->>'maxSnoozes')::int) else 0 end;
  target int := app.wake_final_target(mode, snoozes);
  t_start bigint[];
  t_end bigint[];
  n int;
  success_at bigint;
  score int;
  reason text := 'not_reached';
  status text;
  win_start bigint;
  win_end bigint;
  ring bigint;
  st jsonb;
  done int := 0;
  prev_end bigint;
  cnt int;
begin
  select coalesce(array_agg((r->>'tStart')::bigint order by (r->>'tEnd')::bigint, (r->>'tStart')::bigint), '{}'),
         coalesce(array_agg((r->>'tEnd')::bigint order by (r->>'tEnd')::bigint, (r->>'tStart')::bigint), '{}')
    into t_start, t_end
    from jsonb_array_elements(coalesce(s->'reps', '[]')) r
   where (r->>'tStart')::bigint >= t0 - 30000 and (r->>'tEnd')::bigint <= deadline;
  n := coalesce(array_length(t_end, 1), 0);
  score := n;

  if (s->>'startedAt')::bigint > deadline then
    reason := 'started_after_deadline';
  elsif mtype in ('ringUntilDone', 'escalation') then
    if n >= target then success_at := t_end[target]; end if;
  elsif mtype = 'beatTheClock' then
    ring := (s->>'ringAt')::bigint;
    win_start := case when ring is not null then greatest(t0, least(ring, deadline)) else t0 end;
    win_end := win_start + (mode->>'windowSeconds')::bigint * 1000;
    select count(*) into cnt from unnest(t_end) e where e <= win_end;
    score := cnt;
    if cnt >= target then success_at := t_end[target];
    elsif n >= target then reason := 'window_expired';
    end if;
  elsif mtype = 'sprint' then
    win_start := (s->>'sprintStart')::bigint;
    if win_start is null then
      reason := 'sprint_not_started';
    elsif win_start > deadline or win_start < t0 - 30000 then
      reason := 'sprint_outside_deadline';
    else
      win_end := win_start + (mode->>'windowSeconds')::bigint * 1000;
      select count(*) into cnt from generate_subscripts(t_end, 1) i where t_start[i] >= win_start and t_end[i] <= win_end;
      score := cnt;
      if cnt >= (mode->>'minimumReps')::int then
        select e into success_at from (
          select t_end[i] e, row_number() over (order by i) rn from generate_subscripts(t_end, 1) i
           where t_start[i] >= win_start and t_end[i] <= win_end) x
         where rn = (mode->>'minimumReps')::int;
      elsif (s->>'endedAt')::bigint >= win_end or now_ms >= win_end then
        reason := 'sprint_too_few';
      end if;
    end if;
  elsif mtype = 'sets' then
    for st in select x from jsonb_array_elements(coalesce(s->'sets', '[]')) x
              order by (x->>'start')::bigint loop
      if prev_end is not null
         and (st->>'start')::bigint > prev_end + ((mode->>'restSeconds')::bigint + 30) * 1000 then
        reason := 'rest_too_long';
        exit;
      end if;
      select count(*) into cnt from generate_subscripts(t_end, 1) i
       where t_start[i] >= (st->>'start')::bigint and t_end[i] <= (st->>'end')::bigint;
      exit when cnt < (mode->>'repsPerSet')::int;
      done := done + 1;
      prev_end := (st->>'end')::bigint;
      if done = (mode->>'sets')::int then
        success_at := prev_end;
        exit;
      end if;
    end loop;
    score := done;
  end if;

  if success_at is not null then
    status := 'succeeded'; reason := 'ok';
  elsif s->>'outcome' = 'gaveUp' or now_ms > deadline
        or reason in ('window_expired', 'sprint_too_few', 'rest_too_long', 'sprint_outside_deadline') then
    status := 'failed';
  else
    status := 'in_progress';
  end if;
  if reason = 'started_after_deadline' then status := 'missed'; end if;
  return jsonb_build_object('status', status, 'finalTargetReps', target, 'successAt', success_at, 'score', score,
                            'reason', reason, 'snoozesUsed', snoozes);
end $$;

-- days: [{date, status}], grants: [{date, count}] → streak state + per-day effects.
create or replace function app.streak_fold(days jsonb, grants jsonb) returns jsonb
language plpgsql immutable as $$
declare
  day jsonb;
  g jsonb;
  garr jsonb[];
  gi int := 1;
  cur int := 0; best int := 0; pure int := 0; pure_best int := 0; freezes int := 0;
  paused_month text; paused_count int := 0;
  last_counted text;
  status text;
  effect text;
  effects jsonb := '[]';
begin
  select coalesce(array_agg(x order by x->>'date'), '{}') into garr from jsonb_array_elements(coalesce(grants, '[]')) x;
  for day in select x from jsonb_array_elements(coalesce(days, '[]')) x order by x->>'date' loop
    while gi <= coalesce(array_length(garr, 1), 0) and garr[gi]->>'date' <= day->>'date' loop
      freezes := least(2, freezes + (garr[gi]->>'count')::int);
      gi := gi + 1;
    end loop;
    status := day->>'status';
    if status = 'paused' then
      if substr(day->>'date', 1, 7) = paused_month then paused_count := paused_count + 1;
      else paused_count := 1; end if;
      paused_month := substr(day->>'date', 1, 7);
      if paused_count > 14 then status := 'missed'; end if;
    end if;
    effect := 'neutral';
    if status = 'succeeded' then
      cur := cur + 1; pure := pure + 1;
      best := greatest(best, cur); pure_best := greatest(pure_best, pure);
      last_counted := day->>'date';
      effect := 'plus';
    elsif status in ('failed', 'missed') then
      pure := 0;
      if freezes > 0 then freezes := freezes - 1; effect := 'freeze_used';
      else cur := 0; effect := 'reset'; end if;
    end if;
    effects := effects || jsonb_build_object('date', day->>'date', 'effect', effect);
  end loop;
  return jsonb_build_object('current', cur, 'best', best, 'pureCurrent', pure, 'pureBest', pure_best,
    'freezesAvailable', freezes, 'lastCountedDate', last_counted, 'effects', effects);
end $$;

-- ---------------------------------------------------------------------------
-- Stateful parts
-- ---------------------------------------------------------------------------
create or replace function app.recompute_streak(uid uuid) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare st jsonb;
begin
  st := app.streak_fold(
    (select coalesce(jsonb_agg(jsonb_build_object('date', local_date::text, 'status', status::text)), '[]')
       from public.wake_attempts where user_id = uid),
    (select coalesce(jsonb_agg(jsonb_build_object('date', granted_on::text, 'count', count)), '[]')
       from public.streak_freeze_grants where user_id = uid));
  insert into public.streaks as s (user_id, current, best, pure_current, pure_best, last_counted_date,
                                   freezes_available, updated_at)
  values (uid, (st->>'current')::int, (st->>'best')::int, (st->>'pureCurrent')::int, (st->>'pureBest')::int,
          (st->>'lastCountedDate')::date, (st->>'freezesAvailable')::int, now())
  on conflict (user_id) do update set current = excluded.current, best = excluded.best,
    pure_current = excluded.pure_current, pure_best = excluded.pure_best,
    last_counted_date = excluded.last_counted_date, freezes_available = excluded.freezes_available,
    updated_at = now();
  return st - 'effects';
end $$;

-- Writes final results for past days (missed / failed / paused / skipped) from the schedule snapshots, up to `now`.
-- Days already decided by a session keep their status. Looks back at most 60 days.
create or replace function app.settle_wake_days(uid uuid, now_at timestamptz default now()) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  tz text;
  today date;
  d date;
  plan jsonb;
  settled date;
  first_version date;
  can_advance boolean := true;
begin
  select coalesce(timezone, 'UTC') into tz from public.profiles where id = uid;
  if tz is null then return; end if;
  today := (now_at at time zone tz)::date;
  select settled_through into settled from public.streaks where user_id = uid;
  select min((valid_from at time zone tz)::date) into first_version from public.alarm_schedule_versions where user_id = uid;
  if first_version is null then return; end if;
  d := greatest(coalesce(settled + 1, first_version), first_version, today - 60);
  while d <= today loop
    plan := app.day_plan(uid, d, tz);
    if plan->>'kind' = 'ring' then
      if (plan->>'deadline')::timestamptz < now_at then
        insert into public.wake_attempts (user_id, local_date, occurrence_id, alarm_id, alarm_version, scheduled_at,
                                          deadline_at, mode, status, reason, decided_at)
        values (uid, d, plan->>'occurrenceId', (plan->>'alarmId')::uuid, (plan->>'version')::int,
                (plan->>'t0')::timestamptz, (plan->>'deadline')::timestamptz, plan->'mode', 'missed',
                'no_session', now_at)
        on conflict (user_id, local_date) do update set
          status = 'failed', reason = 'deadline', decided_at = now_at
          where wake_attempts.status in ('scheduled', 'ringing', 'in_progress');
      else
        insert into public.wake_attempts (user_id, local_date, occurrence_id, alarm_id, alarm_version, scheduled_at,
                                          deadline_at, mode, status)
        values (uid, d, plan->>'occurrenceId', (plan->>'alarmId')::uuid, (plan->>'version')::int,
                (plan->>'t0')::timestamptz, (plan->>'deadline')::timestamptz, plan->'mode', 'scheduled')
        on conflict (user_id, local_date) do nothing;
        can_advance := false;
      end if;
    elsif plan->>'kind' in ('paused', 'skipped') then
      if d < today then
        insert into public.wake_attempts (user_id, local_date, status, decided_at)
        values (uid, d, (plan->>'kind')::public.wake_status, now_at)
        on conflict (user_id, local_date) do nothing;
      else
        can_advance := false;
      end if;
    elsif d = today then
      can_advance := false;
    end if;
    if can_advance then settled := d; end if;
    d := d + 1;
  end loop;
  insert into public.streaks (user_id, settled_through) values (uid, settled)
  on conflict (user_id) do update set settled_through = excluded.settled_through;
  perform app.recompute_streak(uid);
end $$;

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
  insert into public.user_stats_alltime as a (user_id, reps_total, wake_points, best_set)
  values (uid, p_reps, wake_pts, p_best_set)
  on conflict (user_id) do update set reps_total = a.reps_total + excluded.reps_total,
    wake_points = a.wake_points + excluded.wake_points, best_set = greatest(a.best_set, excluded.best_set);
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

-- camelCase API shapes (shared/contracts/submit-rep-session.response.schema.json, wake-summary.schema.json)
create or replace function app.streak_json(uid uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select coalesce((select jsonb_build_object('current', current, 'best', best, 'pureCurrent', pure_current,
    'pureBest', pure_best, 'freezesAvailable', freezes_available, 'lastCountedDate', last_counted_date)
    from public.streaks where user_id = uid),
    '{"current":0,"best":0,"pureCurrent":0,"pureBest":0,"freezesAvailable":0,"lastCountedDate":null}')
$$;

create or replace function app.attempt_json(a public.wake_attempts) returns jsonb
language sql stable as $$
  select jsonb_build_object('localDate', a.local_date, 'occurrenceId', a.occurrence_id, 'status', a.status,
    'reason', a.reason, 'scheduledAt', app.utc_iso(a.scheduled_at), 'deadline', app.utc_iso(a.deadline_at),
    'mode', a.mode, 'finalTargetReps', a.final_target_reps, 'snoozesUsed', a.snoozes_used, 'score', a.score,
    'points', a.points)
$$;

-- Applies one validated rep session (called by the Edge Function with the service role). Idempotent by sessionId.
-- p: {userId, deviceId, receivedAt, verified, verification, flags:[{type,severity,details}], log, signature,
--     session: {sessionId, context, occurrenceId, startedAt, endedAt (epoch ms), ringAt, outcome, snoozes,
--               reps:[{tStart,tEnd,quality}], sets, sprintStart, rejected, specVersion, appVersion, platform, bestSet}}
create or replace function app.apply_validated_session(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := (p->>'userId')::uuid;
  s jsonb := p->'session';
  sid uuid := (s->>'sessionId')::uuid;
  existing record;
  received timestamptz := coalesce((p->>'receivedAt')::timestamptz, now());
  started timestamptz := to_timestamp((s->>'startedAt')::bigint / 1000.0);
  ended timestamptz := to_timestamp((s->>'endedAt')::bigint / 1000.0);
  late_h numeric := extract(epoch from (received - ended)) / 3600;
  v_verified boolean := coalesce((p->>'verified')::boolean, false);
  v_verification jsonb := coalesce(p->'verification', '{}');
  v_reps int := jsonb_array_length(coalesce(s->'reps', '[]'));
  avg_q int;
  v_best_set int := coalesce((s->>'bestSet')::int, 0);
  tz text;
  local_d date;
  ctx text := s->>'context';
  occ_alarm uuid;
  occ_date date;
  plan jsonb;
  decision jsonb;
  attempt record;
  wake_result jsonb;
  v_points int := 0;
  prev_best int;
  sessions_before int;
  day_reps int;
  week_reps int;
  f jsonb;
  v_result jsonb;
  st jsonb;
begin
  select * into existing from public.rep_sessions where id = sid;
  if found then
    if existing.user_id <> uid then raise exception 'session_conflict' using errcode = 'P0409'; end if;
    return existing.result;
  end if;
  select coalesce(timezone, 'UTC') into tz from public.profiles where id = uid;
  if tz is null then raise exception 'unknown_user' using errcode = 'P0404'; end if;
  local_d := (started at time zone tz)::date;
  select round(avg((r->>'quality')::int)) into avg_q from jsonb_array_elements(coalesce(s->'reps', '[]')) r;

  -- Server-side soft checks that need history (doc 06 §4).
  select coalesce(sum(reps_total), 0) into day_reps from public.user_stats_daily
   where user_id = uid and day = (started at time zone 'UTC')::date;
  select coalesce(sum(reps_total), 0) into week_reps from public.user_stats_weekly
   where user_id = uid and week_start = (date_trunc('week', started at time zone 'UTC'))::date;
  if v_verified and (day_reps + v_reps > 1000 or week_reps + v_reps > 5000) then
    v_verified := false;
    v_verification := v_verification || '{"hold": "volume_ceiling"}';
    p := jsonb_set(p, '{flags}', coalesce(p->'flags', '[]') || jsonb_build_object('type', 'volume_ceiling',
         'severity', 'soft', 'details', jsonb_build_object('dayReps', day_reps, 'weekReps', week_reps, 'reps', v_reps)));
  end if;
  select value into prev_best from public.personal_records where user_id = uid and record = 'best_set';
  select count(*) into sessions_before from public.rep_sessions where user_id = uid and rep_sessions.verified;
  if v_verified and sessions_before >= 10 and prev_best is not null and v_best_set > prev_best * 1.8 then
    p := jsonb_set(p, '{flags}', coalesce(p->'flags', '[]') || jsonb_build_object('type', 'personal_best_jump',
         'severity', 'soft', 'details', jsonb_build_object('previous', prev_best, 'bestSet', v_best_set)));
  end if;

  insert into public.rep_sessions (id, user_id, device_id, context, occurrence_id, started_at, ended_at,
    reps_counted, best_set, avg_quality, rejected, spec_version, app_version, platform, verified, verification,
    late, received_at)
  values (sid, uid, (p->>'deviceId')::uuid, ctx::public.session_context, s->>'occurrenceId', started, ended, v_reps,
    v_best_set, avg_q, coalesce(s->'rejected', '{}'), (s->>'specVersion')::smallint, s->>'appVersion',
    (s->>'platform')::public.platform_t, v_verified, v_verification, late_h > 48, received);
  begin
    insert into public.rep_session_logs (session_id, log, signature)
    values (sid, coalesce(p->'log', '{}'), coalesce(p->>'signature', 'unsigned:' || sid::text));
  exception when unique_violation then
    raise exception 'duplicate_log' using errcode = 'P0409';
  end;
  for f in select * from jsonb_array_elements(coalesce(p->'flags', '[]')) loop
    insert into public.anti_cheat_flags (user_id, session_id, type, severity, details)
    values (uid, sid, f->>'type', (f->>'severity')::public.flag_severity, f->'details');
  end loop;

  -- Wake challenge: only verified, on-time (≤ 48 h) sessions for today's challenge occurrence (doc 06 §5).
  if ctx = 'wake' and v_verified and late_h <= 48 and s->>'occurrenceId' ~ '^[0-9a-fA-F-]{36}:\d{4}-\d{2}-\d{2}$' then
    occ_alarm := split_part(s->>'occurrenceId', ':', 1)::uuid;
    occ_date := split_part(s->>'occurrenceId', ':', 2)::date;
    plan := app.day_plan(uid, occ_date, tz);
    if plan->>'kind' = 'ring' and (plan->>'alarmId')::uuid = occ_alarm then
      decision := app.decide_wake(plan->'mode', (extract(epoch from (plan->>'t0')::timestamptz) * 1000)::bigint,
                                  (extract(epoch from received) * 1000)::bigint, s);
      insert into public.wake_attempts (user_id, local_date, occurrence_id, alarm_id, alarm_version, scheduled_at,
                                        deadline_at, mode, status)
      values (uid, occ_date, plan->>'occurrenceId', occ_alarm, (plan->>'version')::int, (plan->>'t0')::timestamptz,
              (plan->>'deadline')::timestamptz, plan->'mode', 'scheduled')
      on conflict (user_id, local_date) do nothing;
      select * into attempt from public.wake_attempts where user_id = uid and local_date = occ_date for update;
      -- succeeded is final; failed / missed only give way to a proven success; in_progress never overrides a result.
      if attempt.status <> 'succeeded' and (
           decision->>'status' = 'succeeded'
           or (decision->>'status' in ('failed', 'missed') and attempt.status in ('scheduled', 'ringing', 'in_progress'))
           or (decision->>'status' = 'in_progress' and attempt.status in ('scheduled', 'ringing'))) then
        if decision->>'status' = 'succeeded' then
          v_points := app.wake_points((decision->>'finalTargetReps')::int, plan->'mode'->>'type',
                                    (decision->>'snoozesUsed')::int, coalesce(avg_q, 0));
        end if;
        update public.wake_attempts set status = (decision->>'status')::public.wake_status,
          reason = decision->>'reason', session_id = sid, final_target_reps = (decision->>'finalTargetReps')::int,
          snoozes_used = (decision->>'snoozesUsed')::int, score = (decision->>'score')::int, points = v_points,
          decided_at = case when decision->>'status' = 'in_progress' then null else received end
        where id = attempt.id;
        if v_points > 0 then
          perform app.bump_stats(uid, (plan->>'t0')::timestamptz, null, null, 0, 0, null, v_points, true);
        end if;
      end if;
      select * into attempt from public.wake_attempts where id = attempt.id;
      wake_result := jsonb_build_object('occurrenceId', plan->>'occurrenceId', 'status', attempt.status,
        'reason', attempt.reason, 'points', attempt.points, 'finalTargetReps', attempt.final_target_reps,
        'score', attempt.score, 'deadline', plan->>'deadline');
    else
      wake_result := jsonb_build_object('occurrenceId', s->>'occurrenceId', 'status', 'not_challenge',
                                        'reason', 'not_todays_challenge_occurrence');
    end if;
  end if;

  perform app.bump_stats(uid, started, local_d, ctx, v_reps, v_best_set, avg_q, 0, v_verified and late_h <= 48);
  if v_verified and v_best_set > coalesce(prev_best, 0) then
    insert into public.personal_records (user_id, record, value, session_id, achieved_at)
    values (uid, 'best_set', v_best_set, sid, ended)
    on conflict (user_id, record) do update set value = excluded.value, session_id = excluded.session_id,
      achieved_at = excluded.achieved_at;
  end if;

  perform app.settle_wake_days(uid, received);
  st := app.streak_json(uid);
  v_result := jsonb_build_object('sessionId', sid, 'verified', v_verified, 'late', late_h > 48, 'repsCounted', v_reps,
    'avgQuality', avg_q, 'wake', wake_result, 'streak', st,
    'totals', jsonb_build_object(
      'repsToday', (select reps_total from public.user_stats_local_daily where user_id = uid and local_date = local_d),
      'repsAllTime', (select reps_total from public.user_stats_alltime where user_id = uid)));
  update public.rep_sessions set result = v_result where id = sid;
  return v_result;
end $$;

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
create or replace function public.apply_validated_session(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return app.apply_validated_session(p);
end $$;
revoke all on function public.apply_validated_session(jsonb) from public, anon, authenticated;
grant execute on function public.apply_validated_session(jsonb) to service_role;

-- Wake tab summary (PS-10…PS-15): settles past days, returns streak, today's plan + attempt, last 14 days.
create or replace function public.get_wake_summary() returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := auth.uid();
  tz text;
  today date;
begin
  if uid is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  perform app.settle_wake_days(uid, now());
  select coalesce(timezone, 'UTC') into tz from public.profiles where id = uid;
  today := (now() at time zone tz)::date;
  return jsonb_build_object(
    'today', today,
    'plan', app.day_plan(uid, today, tz),
    'streak', app.streak_json(uid),
    'attempts', coalesce((select jsonb_agg(app.attempt_json(a) order by a.local_date desc)
                            from (select * from public.wake_attempts where user_id = uid
                                   order by local_date desc limit 14) a), '[]'));
end $$;
revoke all on function public.get_wake_summary() from public, anon;
grant execute on function public.get_wake_summary() to authenticated;

grant execute on all functions in schema app to service_role;
