begin;
\ir _helpers.psql
select plan(19);

create temp table ids as
  select tests.create_user('ana@example.com') as ana, tests.create_user('tom@example.com') as tom;
grant select on ids to authenticated, anon, service_role;

create or replace function tests.alarm(id text, version int, updated text, target int default 20) returns jsonb
language sql as $$
  select jsonb_build_object(
    'id', id, 'version', version, 'label', 'Up', 'enabled', true, 'countsForChallenge', true, 'kind', 'weekly',
    'weekly', jsonb_build_object('mon', '06:30', 'tue', '06:30'), 'overrides', '[]'::jsonb, 'pause', null,
    'mode', jsonb_build_object('type', 'ringUntilDone', 'targetReps', target),
    'sound', jsonb_build_object('id', 'bundled.pulse'), 'updatedAt', updated)
$$;

-- direct writes are blocked --------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select throws_ok($$ insert into public.alarm_schedules (id, user_id, version, enabled, counts_for_challenge, data)
                    values (gen_random_uuid(), auth.uid(), 1, true, true, '{}') $$, '42501', null,
  'clients cannot insert alarm_schedules directly');

-- create ----------------------------------------------------------------------------------
select is(
  public.sync_alarms(jsonb_build_array(jsonb_build_object('op', 'upsert',
    'alarm', tests.alarm('a0000000-0000-4000-8000-000000000001', 1, '2026-10-20T08:00:00Z'))))->'results'->0->>'status',
  'ok', 'a valid alarm is accepted');
select is((select count(*)::int from public.alarm_schedules), 1, 'owner sees the alarm');
select is((select count(*)::int from public.alarm_schedule_versions), 1, 'a version row is written');

-- invalid ---------------------------------------------------------------------------------
select is(
  public.sync_alarms(jsonb_build_array(jsonb_build_object('op', 'upsert',
    'alarm', tests.alarm('a0000000-0000-4000-8000-000000000002', 1, '2026-10-20T08:00:00Z', 3))))->'results'->0->'errors',
  '["mode.targetReps"]'::jsonb, 'invalid alarms are rejected with the shared error codes');
select is((select count(*)::int from public.alarm_schedules), 1, 'and are not stored');

-- update with a newer version ---------------------------------------------------------------
select is(
  public.sync_alarms(jsonb_build_array(jsonb_build_object('op', 'upsert',
    'alarm', tests.alarm('a0000000-0000-4000-8000-000000000001', 2, '2026-10-20T09:00:00Z', 30))))->'results'->0->>'version',
  '2', 'newer device version wins');
select is((select (data->'mode'->>'targetReps')::int from public.alarm_schedules), 30, 'server copy updated');

-- stale edit: same version, older updatedAt → conflict with server copy -----------------------
select is(
  public.sync_alarms(jsonb_build_array(jsonb_build_object('op', 'upsert',
    'alarm', tests.alarm('a0000000-0000-4000-8000-000000000001', 2, '2026-10-20T07:00:00Z', 40))))->'results'->0->>'status',
  'conflict', 'an older edit of the same version is a conflict');
select is((select (data->'mode'->>'targetReps')::int from public.alarm_schedules), 30, 'conflict leaves the server copy');

-- same version but newer edit (another device) → device wins, version bumped -------------------
select is(
  public.sync_alarms(jsonb_build_array(jsonb_build_object('op', 'upsert',
    'alarm', tests.alarm('a0000000-0000-4000-8000-000000000001', 2, '2026-10-20T10:00:00Z', 50))))->'results'->0->>'version',
  '3', 'a newer edit with the same version wins and gets the next version');
select is((select count(*)::int from public.alarm_schedule_versions), 3, 'history keeps every accepted version');

-- other users -------------------------------------------------------------------------------
select tests.authenticate_as((select tom from ids));
select is((select count(*)::int from public.alarm_schedules), 0, 'other users cannot see the alarm');
select is((select count(*)::int from public.alarm_schedule_versions), 0, 'nor its history');
select is(
  public.sync_alarms(jsonb_build_array(jsonb_build_object('op', 'upsert',
    'alarm', tests.alarm('a0000000-0000-4000-8000-000000000001', 9, '2026-10-21T10:00:00Z'))))->'results'->0->>'status',
  'invalid', 'nobody can overwrite another user''s alarm id');
select is(
  public.sync_alarms(jsonb_build_array(jsonb_build_object('op', 'delete', 'id', 'a0000000-0000-4000-8000-000000000001')))
    ->'results'->0->>'status',
  'notFound', 'nor delete it');

-- delete (soft) -----------------------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select is(jsonb_array_length(public.sync_alarms(jsonb_build_array(jsonb_build_object(
  'op', 'delete', 'id', 'a0000000-0000-4000-8000-000000000001', 'version', 4)))->'alarms'), 0,
  'deleted alarms are not returned');
select ok((select deleted_at is not null from public.alarm_schedules), 'delete is a soft delete (history for snapshots)');

-- anon ----------------------------------------------------------------------------------------
select tests.as_anon();
select throws_ok($$ select public.sync_alarms('[]') $$, '42501', null, 'anon cannot sync alarms');

select * from finish();
rollback;
