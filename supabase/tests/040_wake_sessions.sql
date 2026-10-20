-- Wake sessions end to end (P4-01/P4-03): RLS, apply_validated_session, idempotency, settle, streak, stats.
begin;
\ir _helpers.psql
select plan(28);

create temp table ids as
  select tests.create_user('ana@example.com') as ana, tests.create_user('tom@example.com') as tom;
grant select on ids to authenticated, anon, service_role;
update public.profiles set timezone = 'Europe/Prague';

create or replace function tests.ms(ts text) returns bigint language sql as
$$ select (extract(epoch from ts::timestamptz) * 1000)::bigint $$;

-- A rep session payload as the Edge Function sends it (times = server epoch ms).
create or replace function tests.payload(uid uuid, sid text, occ text, first_rep text, n int, ctx text default 'wake',
                                         received text default '2026-10-20T05:10:00Z', sig text default null,
                                         verified boolean default true) returns jsonb
language sql as $$
  select jsonb_build_object(
    'userId', uid, 'receivedAt', received, 'verified', verified, 'verification', '{}'::jsonb,
    'signature', coalesce(sig, 'sig-' || sid), 'log', '{}'::jsonb,
    'session', jsonb_build_object(
      'sessionId', sid, 'context', ctx, 'occurrenceId', occ,
      'startedAt', tests.ms(first_rep) - 10000, 'endedAt', tests.ms(first_rep) + n * 2000 + 2000,
      'ringAt', tests.ms('2026-10-20T05:00:00Z'), 'outcome', 'completed', 'snoozes', 0,
      'reps', (select jsonb_agg(jsonb_build_object('tStart', tests.ms(first_rep) + i * 2000,
                                                   'tEnd', tests.ms(first_rep) + i * 2000 + 1500, 'quality', 92))
                 from generate_series(0, n - 1) i),
      'specVersion', 1, 'appVersion', '0.1.0 (1)', 'platform', 'ios', 'bestSet', n, 'rejected', '{}'::jsonb))
$$;

-- Ana: challenge alarm every day 07:00 Prague since 2026-10-17.
insert into public.alarm_schedules (id, user_id, version, enabled, counts_for_challenge, data)
select 'a0000000-0000-4000-8000-000000000001', ana, 1, true, true, jsonb_build_object(
  'id', 'a0000000-0000-4000-8000-000000000001', 'version', 1, 'enabled', true, 'countsForChallenge', true,
  'kind', 'weekly', 'weekly', jsonb_build_object('mon','07:00','tue','07:00','wed','07:00','thu','07:00','fri','07:00',
  'sat','07:00','sun','07:00'), 'overrides', '[]'::jsonb, 'pause', null,
  'mode', jsonb_build_object('type','ringUntilDone','targetReps',20)) from ids;
insert into public.alarm_schedule_versions (alarm_id, user_id, version, data, valid_from)
select id, user_id, 1, data, '2026-10-17T00:00:00Z' from public.alarm_schedules;

-- clients can't write or call the service function ---------------------------------------------
select tests.authenticate_as((select ana from ids));
select throws_ok($$ insert into public.rep_sessions (id, user_id, context, started_at, ended_at, reps_counted,
                    spec_version, app_version) values (gen_random_uuid(), auth.uid(), 'training', now(), now(), 999,
                    1, 'x') $$, '42501', null, 'clients cannot insert rep_sessions');
select throws_ok($$ insert into public.wake_attempts (user_id, local_date, status) values (auth.uid(), current_date,
                    'succeeded') $$, '42501', null, 'clients cannot insert wake_attempts');
select throws_ok($$ update public.streaks set current = 999 $$, '42501', null, 'clients cannot update streaks');
select throws_ok($$ insert into public.user_stats_daily (user_id, day, reps_total) values (auth.uid(), current_date, 1) $$,
                 '42501', null, 'clients cannot write leaderboard stats');
select throws_ok($$ select public.apply_validated_session('{}') $$, '42501', null,
                 'apply_validated_session is service-role only');

-- a successful wake session ----------------------------------------------------------------------
select tests.as_service();
create temp table r1 as select public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001:2026-10-20',
  '2026-10-20T05:02:00Z', 20)) as r;
grant select on r1 to authenticated, anon, service_role;
select is((select r->'wake'->>'status' from r1), 'succeeded', '20 reps 2 min after the ring → succeeded');
select is((select (r->'wake'->>'points')::int from r1), 17, 'wake points: 10 + 20/5 + quality 92 → 17');
select is((select (r->'streak'->>'current')::int from r1), 1, 'streak 1 (the three days before were missed)');
select is((select (r->'totals'->>'repsToday')::int from r1), 20, 'today total');

select tests.as_owner();
select is((select count(*)::int from public.wake_attempts where status = 'missed'), 3,
          'settle wrote missed for 17–19 Oct (alarm, no session)');
select is((select wake_points from public.user_stats_daily where day = '2026-10-20'), 17, 'points in daily stats');
select is((select reps_wake from public.user_stats_daily where day = '2026-10-20'), 20, 'wake reps in daily stats');
select is((select value from public.personal_records where record = 'best_set'), 20, 'personal record');

-- idempotent replay ------------------------------------------------------------------------------
select tests.as_service();
select is(public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001:2026-10-20',
  '2026-10-20T05:02:00Z', 20)), (select r from r1), 'same sessionId returns the stored result');
select tests.as_owner();
select is((select reps_total from public.user_stats_alltime), 20::bigint, 'replay did not double the stats');

-- a replayed signature under a new session id is rejected ----------------------------------------
select tests.as_service();
select throws_ok(format($$ select public.apply_validated_session(tests.payload(%L,
  'f0000000-0000-4000-8000-000000000002', null, '2026-10-20T08:00:00Z', 5, 'training', '2026-10-20T08:05:00Z',
  'sig-f0000000-0000-4000-8000-000000000001')) $$, (select ana from ids)), 'P0409', 'duplicate_log',
  'the same signed log cannot be submitted twice');

-- training counts for stats, not for the wake attempt ---------------------------------------------
select is((public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000003', null, '2026-10-20T16:00:00Z', 15, 'training',
  '2026-10-20T16:05:00Z'))->'totals'->>'repsToday')::int, 35, 'training adds to today');

-- wrong occurrence (not today's challenge) ---------------------------------------------------------
select is(public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000009:2026-10-20',
  '2026-10-20T05:02:00Z', 20))->'wake'->>'status', 'not_challenge', 'a practice / unknown alarm is not the challenge');

-- unverified sessions never count competitively ---------------------------------------------------
select is(public.apply_validated_session(tests.payload((select tom from ids),
  'f0000000-0000-4000-8000-000000000005', null, '2026-10-20T09:00:00Z', 30, 'training', '2026-10-20T09:05:00Z',
  null, false))->>'verified', 'false', 'unverified');
select tests.as_owner();
select is((select count(*)::int from public.user_stats_daily where user_id = (select tom from ids)), 0,
          'unverified reps stay out of leaderboard stats');
select is((select reps_total from public.user_stats_local_daily where user_id = (select tom from ids)), 30,
          'but count for personal stats');

-- late upload of a session that started after the deadline → missed stays -------------------------
select tests.as_service();
select is(public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001:2026-10-19',
  '2026-10-19T05:40:00Z', 20, 'wake', '2026-10-20T10:00:00Z'))->'wake'->>'status', 'missed',
  'reps after the deadline cannot rescue a missed day');

-- offline phone: yesterday's successful session arrives a day later → missed becomes succeeded -----
select is(public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001:2026-10-18',
  '2026-10-18T05:05:00Z', 20, 'wake', '2026-10-19T12:00:00Z'))->'wake'->>'status', 'succeeded',
  'a late (≤ 48 h) proof of success turns a missed day into a success');

-- RLS: Tom sees nothing of Ana -----------------------------------------------------------------------
select tests.authenticate_as((select tom from ids));
select is((select count(*)::int from public.rep_sessions), 1, 'Tom sees only his own session');
select is((select count(*)::int from public.wake_attempts), 0, 'and no wake attempts of Ana');
select is((select count(*)::int from public.user_stats_alltime), 1, 'only his own all-time row');
select throws_ok($$ select * from public.rep_session_logs $$, '42501', null, 'raw logs are service-only');

-- summary RPC --------------------------------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select ok(public.get_wake_summary() ? 'streak', 'get_wake_summary returns the streak');

select * from finish();
rollback;
