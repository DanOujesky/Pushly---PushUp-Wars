-- 0005 — alarm schedules + version history + sync RPC (doc 04 §2/§7, doc 11 §4, roadmap P2-09)
--
-- Alarms are scheduled on the device from local storage and work offline (CLAUDE.md §4.4). The server copy exists
-- for the Wake Challenge (schedule snapshot 15 min before T0, doc 04 §7) and to restore alarms on a new phone.
-- Clients never write these tables directly: `sync_alarms` validates (same rules as the apps, vectors in
-- shared/test-vectors/alarm-validation) and writes the version history.

create table public.alarm_schedules (
  id uuid primary key,                              -- generated on the device
  user_id uuid not null references public.profiles(id) on delete cascade,
  version int not null check (version >= 1),
  enabled boolean not null,
  counts_for_challenge boolean not null,
  data jsonb not null,                              -- full AlarmSchedule (shared/contracts/alarm-schedule.schema.json)
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index alarm_schedules_user_idx on public.alarm_schedules(user_id) where deleted_at is null;

create table public.alarm_schedule_versions (       -- history for the 15-min snapshot rule (doc 04 §7)
  alarm_id uuid not null references public.alarm_schedules(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  version int not null,
  data jsonb,                                       -- null = deleted from this moment
  valid_from timestamptz not null default now(),
  primary key (alarm_id, version)
);
create index alarm_schedule_versions_user_idx on public.alarm_schedule_versions(user_id, valid_from);

alter table public.alarm_schedules enable row level security;
alter table public.alarm_schedule_versions enable row level security;
revoke all on public.alarm_schedules, public.alarm_schedule_versions from anon;
revoke insert, update, delete on public.alarm_schedules, public.alarm_schedule_versions from authenticated;

create policy alarm_schedules_select_own on public.alarm_schedules
  for select to authenticated using (user_id = auth.uid());
create policy alarm_schedule_versions_select_own on public.alarm_schedule_versions
  for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Validation — mirror of tools/reference/pushly_ref/validation.py (and AlarmValidation on iOS/Android).
-- Returns error codes; empty array = valid. Tested against the shared vectors (supabase/tests/031_*).
-- ---------------------------------------------------------------------------
create or replace function app.alarm_int_in(v jsonb, lo int, hi int) returns boolean
language sql immutable as $$
  select v is not null and jsonb_typeof(v) = 'number' and (v #>> '{}') ~ '^-?\d+$'
     and (v #>> '{}')::numeric between lo and hi
$$;

create or replace function app.alarm_is_time(v text) returns boolean
language sql immutable as $$ select v ~ '^([01]\d|2[0-3]):[0-5]\d$' $$;

create or replace function app.alarm_parse_date(v text) returns date
language plpgsql immutable as $$
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return v::date;
exception when others then
  return null;
end $$;

create or replace function app.alarm_validation_errors(s jsonb, today date) returns text[]
language plpgsql immutable as $$
declare
  errors text[] := '{}';
  kind text := s->>'kind';
  weekly jsonb := coalesce(s->'weekly', '{}'::jsonb);
  overrides jsonb := coalesce(s->'overrides', '[]'::jsonb);
  ov jsonb;
  d date;
  seen date[] := '{}';
  day text;
  pause jsonb := s->'pause';
  pf date; pt date;
  m jsonb := coalesce(s->'mode', '{}'::jsonb);
  mt text := m->>'type';
  has_day boolean := false;
begin
  if kind is null or kind not in ('weekly', 'oneOff') then errors := errors || 'kind.invalid'; end if;

  if kind = 'weekly' then
    if jsonb_typeof(weekly) <> 'object' then weekly := '{}'::jsonb; end if;
    if exists (select 1 from jsonb_object_keys(weekly) k where k not in ('mon','tue','wed','thu','fri','sat','sun')) then
      errors := errors || 'weekly.unknownDay';
    end if;
    for day in select k from jsonb_object_keys(weekly) k loop
      if jsonb_typeof(weekly->day) <> 'null' then
        if not coalesce(app.alarm_is_time(weekly->>day), false) or jsonb_typeof(weekly->day) <> 'string' then
          errors := errors || ('weekly.' || day || '.time');
        end if;
        if coalesce(weekly->>day, '') <> '' then has_day := true; end if;
      end if;
    end loop;
    if not has_day and jsonb_array_length(overrides) = 0 then errors := errors || 'weekly.empty'; end if;
    if jsonb_array_length(overrides) > 60 then errors := errors || 'overrides.tooMany'; end if;
    for ov in select value from jsonb_array_elements(overrides) loop
      d := app.alarm_parse_date(ov->>'date');
      if d is null then
        errors := errors || 'overrides.date';
        continue;
      end if;
      if d < today then errors := errors || 'overrides.past'; end if;
      if d = any(seen) then errors := errors || 'overrides.duplicate'; end if;
      seen := seen || d;
      if coalesce((ov->>'skip')::boolean, false) is not true and not coalesce(app.alarm_is_time(ov->>'time'), false) then
        errors := errors || 'overrides.time';
      end if;
    end loop;
  end if;

  if kind = 'oneOff' then
    if coalesce(s->>'oneOff', '') !~ '^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d$'
       or app.alarm_parse_date(left(s->>'oneOff', 10)) is null then
      errors := errors || 'oneOff.invalid';
    end if;
  end if;

  if pause is not null and jsonb_typeof(pause) = 'object' then
    pf := app.alarm_parse_date(pause->>'from');
    pt := app.alarm_parse_date(pause->>'to');
    if pf is null or pt is null then
      errors := errors || 'pause.invalid';
    elsif pt < pf then
      errors := errors || 'pause.order';
    elsif (pt - pf) + 1 > 30 then
      errors := errors || 'pause.tooLong';
    end if;
  end if;

  if mt in ('ringUntilDone', 'beatTheClock', 'escalation') and not app.alarm_int_in(m->'targetReps', 5, 100) then
    errors := errors || 'mode.targetReps';
  end if;
  if mt = 'beatTheClock' and not app.alarm_int_in(m->'windowSeconds', 30, 600) then
    errors := errors || 'mode.windowSeconds';
  end if;
  if mt = 'sprint' then
    if not (app.alarm_int_in(m->'windowSeconds', 30, 120) and (m->>'windowSeconds')::int in (30, 60, 120)) then
      errors := errors || 'mode.windowSeconds';
    end if;
    if not app.alarm_int_in(m->'minimumReps', 5, 100) then errors := errors || 'mode.minimumReps'; end if;
  end if;
  if mt = 'sets' then
    if not app.alarm_int_in(m->'sets', 2, 5) then errors := errors || 'mode.sets'; end if;
    if not app.alarm_int_in(m->'repsPerSet', 5, 50) then errors := errors || 'mode.repsPerSet'; end if;
    if not app.alarm_int_in(m->'restSeconds', 15, 180) then errors := errors || 'mode.restSeconds'; end if;
  end if;
  if mt = 'escalation' then
    if not app.alarm_int_in(m->'snoozeAddsReps', 1, 20) then errors := errors || 'mode.snoozeAddsReps'; end if;
    if not app.alarm_int_in(m->'snoozeMinutes', 1, 10) then errors := errors || 'mode.snoozeMinutes'; end if;
    if not app.alarm_int_in(m->'maxSnoozes', 1, 5) then errors := errors || 'mode.maxSnoozes'; end if;
  end if;
  if mt is null or mt not in ('ringUntilDone', 'beatTheClock', 'sprint', 'sets', 'escalation') then
    errors := errors || 'mode.type';
  end if;
  return errors;
end $$;

-- ---------------------------------------------------------------------------
-- sync_alarms(changes) — the device sends its outbox, the server answers per change and returns all alarms.
--
-- changes: [{ "op": "upsert", "alarm": AlarmSchedule } | { "op": "delete", "id": uuid, "version": int }]
-- result:  { "results": [{ "id", "status": ok|conflict|invalid|limit|notFound, "version"?, "errors"?, "server"? }],
--            "alarms": [AlarmSchedule …] }   -- every non-deleted alarm of the user (restore on a new phone)
--
-- Concurrency (doc 12 §1): a newer device version wins; on an equal/older version the newer `updatedAt` wins
-- ("device wins if its edit is newer") — otherwise the server copy is returned as a conflict.
-- ---------------------------------------------------------------------------
create or replace function public.sync_alarms(changes jsonb) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := auth.uid();
  tz text;
  today date;
  c jsonb;
  a jsonb;
  aid uuid;
  existing public.alarm_schedules;
  incoming_version int;
  new_version int;
  errs text[];
  results jsonb := '[]'::jsonb;
  active_count int;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if jsonb_typeof(changes) <> 'array' then raise exception 'changes must be an array' using errcode = '22023'; end if;
  if jsonb_array_length(changes) > 50 then raise exception 'too many changes' using errcode = '22023'; end if;

  select coalesce(timezone, 'UTC') into tz from public.profiles where id = uid;
  today := (now() at time zone coalesce(tz, 'UTC'))::date;

  for c in select value from jsonb_array_elements(changes) loop
    if c->>'op' = 'delete' then
      begin
        aid := (c->>'id')::uuid;
      exception when others then
        results := results || jsonb_build_object('id', c->>'id', 'status', 'invalid', 'errors', jsonb_build_array('id'));
        continue;
      end;
      select * into existing from public.alarm_schedules where id = aid and user_id = uid for update;
      if not found then
        results := results || jsonb_build_object('id', aid, 'status', 'notFound');
        continue;
      end if;
      if existing.deleted_at is null then
        new_version := greatest(existing.version + 1, coalesce((c->>'version')::int, 0));
        update public.alarm_schedules set deleted_at = now(), version = new_version, updated_at = now() where id = aid;
        insert into public.alarm_schedule_versions (alarm_id, user_id, version, data) values (aid, uid, new_version, null)
          on conflict (alarm_id, version) do nothing;
      end if;
      results := results || jsonb_build_object('id', aid, 'status', 'ok');
      continue;
    end if;

    a := c->'alarm';
    begin
      aid := (a->>'id')::uuid;
    exception when others then
      results := results || jsonb_build_object('id', a->>'id', 'status', 'invalid', 'errors', jsonb_build_array('id'));
      continue;
    end;
    if a is null or jsonb_typeof(a) <> 'object' or c->>'op' <> 'upsert' then
      results := results || jsonb_build_object('id', aid, 'status', 'invalid', 'errors', jsonb_build_array('op'));
      continue;
    end if;

    -- Overrides in the past are history, not errors (the device drops them too).
    a := jsonb_set(a, '{overrides}', coalesce((
      select jsonb_agg(o) from jsonb_array_elements(coalesce(a->'overrides', '[]'::jsonb)) o
      where app.alarm_parse_date(o->>'date') is null or app.alarm_parse_date(o->>'date') >= today
    ), '[]'::jsonb));
    errs := app.alarm_validation_errors(a, today);
    if char_length(coalesce(a->>'label', '')) > 40 then errs := errs || 'label.tooLong'; end if;
    if cardinality(errs) > 0 then
      results := results || jsonb_build_object('id', aid, 'status', 'invalid', 'errors', to_jsonb(errs));
      continue;
    end if;

    incoming_version := greatest(coalesce((a->>'version')::int, 1), 1);
    select * into existing from public.alarm_schedules where id = aid for update;
    if found and existing.user_id <> uid then
      results := results || jsonb_build_object('id', aid, 'status', 'invalid', 'errors', jsonb_build_array('id'));
      continue;
    end if;

    if not found or existing.deleted_at is not null then
      select count(*) into active_count from public.alarm_schedules where user_id = uid and deleted_at is null;
      if active_count >= 20 then
        results := results || jsonb_build_object('id', aid, 'status', 'limit');
        continue;
      end if;
    end if;

    if found and existing.deleted_at is null and incoming_version <= existing.version
       and coalesce(a->>'updatedAt', '') <= coalesce(existing.data->>'updatedAt', '') then
      results := results || jsonb_build_object('id', aid, 'status', 'conflict', 'version', existing.version, 'server', existing.data);
      continue;
    end if;

    new_version := case when found then greatest(incoming_version, existing.version + 1) else incoming_version end;
    a := jsonb_set(a, '{version}', to_jsonb(new_version));
    if found then
      update public.alarm_schedules
        set version = new_version, enabled = coalesce((a->>'enabled')::boolean, true),
            counts_for_challenge = coalesce((a->>'countsForChallenge')::boolean, true),
            data = a, deleted_at = null, updated_at = now()
        where id = aid;
    else
      insert into public.alarm_schedules (id, user_id, version, enabled, counts_for_challenge, data)
        values (aid, uid, new_version, coalesce((a->>'enabled')::boolean, true),
                coalesce((a->>'countsForChallenge')::boolean, true), a);
    end if;
    insert into public.alarm_schedule_versions (alarm_id, user_id, version, data) values (aid, uid, new_version, a)
      on conflict (alarm_id, version) do update set data = excluded.data, valid_from = now();
    results := results || jsonb_build_object('id', aid, 'status', 'ok', 'version', new_version);
  end loop;

  return jsonb_build_object(
    'results', results,
    'alarms', coalesce((select jsonb_agg(data order by created_at) from public.alarm_schedules
                        where user_id = uid and deleted_at is null), '[]'::jsonb)
  );
end $$;

revoke all on function public.sync_alarms(jsonb) from public, anon;
grant execute on function public.sync_alarms(jsonb) to authenticated;
