-- Progress end to end (P5-01/P5-04): XP + level + achievements from apply_validated_session, get_stats,
-- get_achievements, RLS. Rule details are covered by the generated 061_progress_vectors.sql.
begin;
\ir _helpers.psql
select plan(23);

create temp table ids as
  select tests.create_user('ana@example.com') as ana, tests.create_user('tom@example.com') as tom;
grant select on ids to authenticated, anon, service_role;
update public.profiles set timezone = 'Europe/Prague';

create or replace function tests.ms(ts text) returns bigint language sql as
$$ select (extract(epoch from ts::timestamptz) * 1000)::bigint $$;
create or replace function tests.payload(uid uuid, sid text, occ text, first_rep text, n int, ctx text default 'wake',
                                         verified boolean default true) returns jsonb
language sql as $$
  select jsonb_build_object(
    'userId', uid, 'receivedAt', '2026-10-20T05:10:00Z', 'verified', verified, 'verification', '{}'::jsonb,
    'signature', 'sig-' || sid, 'log', '{}'::jsonb,
    'session', jsonb_build_object(
      'sessionId', sid, 'context', ctx, 'occurrenceId', occ,
      'startedAt', tests.ms(first_rep) - 10000, 'endedAt', tests.ms(first_rep) + n * 2000 + 2000,
      'ringAt', tests.ms('2026-10-20T05:00:00Z'), 'outcome', 'completed', 'snoozes', 0,
      'reps', (select jsonb_agg(jsonb_build_object('tStart', tests.ms(first_rep) + i * 2000,
                                                   'tEnd', tests.ms(first_rep) + i * 2000 + 1500, 'quality', 92))
                 from generate_series(0, n - 1) i),
      'specVersion', 1, 'appVersion', '0.1.0 (1)', 'platform', 'ios', 'bestSet', n, 'rejected', '{}'::jsonb))
$$;

insert into public.alarm_schedules (id, user_id, version, enabled, counts_for_challenge, data)
select 'a0000000-0000-4000-8000-000000000001', ana, 1, true, true, jsonb_build_object(
  'id', 'a0000000-0000-4000-8000-000000000001', 'version', 1, 'enabled', true, 'countsForChallenge', true,
  'kind', 'weekly', 'weekly', jsonb_build_object('mon','07:00','tue','07:00','wed','07:00','thu','07:00','fri','07:00',
  'sat','07:00','sun','07:00'), 'overrides', '[]'::jsonb, 'pause', null,
  'mode', jsonb_build_object('type','ringUntilDone','targetReps',20)) from ids;
insert into public.alarm_schedule_versions (alarm_id, user_id, version, data, valid_from)
select id, user_id, 1, data, '2026-10-20T00:00:00Z' from public.alarm_schedules;

-- clients cannot touch progress ---------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select throws_ok($$ insert into public.user_achievements (user_id, achievement_id) values (auth.uid(), 'first_wake') $$,
                 '42501', null, 'clients cannot grant themselves achievements');
select throws_ok($$ update public.achievement_definitions set xp = 99999 $$, '42501', null,
                 'clients cannot edit definitions');
select is((select count(*)::int from public.achievement_definitions), 44, 'definitions are readable');

-- wake session: 20 reps (+20 XP) + succeeded wake (+20 XP) + first_wake (50) + textbook (200) ------------
select tests.as_service();
create temp table r1 as select public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001:2026-10-20',
  '2026-10-20T05:02:00Z', 20)) as r;
grant select on r1 to authenticated, anon, service_role;
select is((select (r->'progress'->>'xpGained')::int from r1), 40, '1 XP per rep + 20 for the wake');
select is((select (r->'progress'->>'xp')::int from r1), 290, 'achievement XP added');
select is((select (r->'progress'->>'level')::int from r1), 3, 'level 3');
select is((select (r->'progress'->>'levelUp')::boolean from r1), true, 'level up flagged');
select is((select jsonb_agg(a->>'id') from r1, jsonb_array_elements(r->'progress'->'newAchievements') a),
          '["first_wake","textbook"]'::jsonb, 'new achievements in definition order');
select is((select (r->>'newBestSet')::boolean from r1), false, 'first ever set is not a "new best" celebration');

-- training session the same day: 60 reps at quality 92 → day_50, set_25, set_50, clean_fifty, then level_5 -----------------------
create temp table r2 as select public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000002', null, '2026-10-20T06:00:00Z', 60, 'training')) as r;
grant select on r2 to authenticated, anon, service_role;
select is((select jsonb_agg(a->>'id') from r2, jsonb_array_elements(r->'progress'->'newAchievements') a),
          '["day_50","set_25","set_50","clean_fifty","level_5"]'::jsonb,
          'day, set, quality and (from the XP just earned) level achievements');
select is((select (r->'progress'->>'xp')::int from r2), 1430, 'XP accumulates (60 reps + 80 + 100 + 300 + 600)');
select is((select (r->>'newBestSet')::boolean from r2), true, 'beat the previous best set');

-- unverified session: no XP, no achievements ------------------------------------------------------
create temp table r3 as select public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000003', null, '2026-10-20T07:00:00Z', 30, 'training', false)) as r;
grant select on r3 to authenticated, anon, service_role;
select is((select (r->'progress'->>'xpGained')::int from r3), 0, 'unverified reps give no XP');
select is((select jsonb_array_length(r->'progress'->'newAchievements') from r3), 0, 'and unlock nothing');

-- replay does not award twice ------------------------------------------------------------------
select is(public.apply_validated_session(tests.payload((select ana from ids),
  'f0000000-0000-4000-8000-000000000002', null, '2026-10-20T06:00:00Z', 60, 'training')), (select r from r2),
  'replay returns the stored result');
select tests.as_owner();
select is((select xp from public.profiles where id = (select ana from ids)), 1430, 'replay gave no extra XP');

-- read side -------------------------------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select is((select count(*)::int from public.user_achievements), 7, 'ana sees her achievements');
select is((select count(*)::int from jsonb_array_elements(public.get_achievements()) a where a->>'unlockedAt' is not null),
          7, 'get_achievements marks unlocked ones');
select is(jsonb_array_length(public.get_achievements()), 44, 'get_achievements lists every definition');
select is((public.get_stats('all')->'records'->>'bestSet')::int, 60, 'stats: best set record');
select is((public.get_stats('all')->'achievements'->>'unlocked')::int, 7, 'stats: achievement count');
select throws_ok($$ select public.get_stats('decade') $$, '22023', null, 'unknown period rejected');

select tests.authenticate_as((select tom from ids));
select is((select count(*)::int from public.user_achievements), 0, 'tom cannot see ana''s achievements');

select * from finish();
rollback;
