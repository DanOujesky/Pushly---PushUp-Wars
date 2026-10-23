-- FRONT placement is personal only (D-064): stored on the session, counts for personal stats and XP, not for the
-- competitive tables (leaderboards / clan wars) and gives no battle reps.
begin;
\ir _helpers.psql
select plan(8);

create temp table ids as select tests.create_user('front_a@example.com') a, tests.create_user('front_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles set timezone = 'Europe/Prague';

create or replace function tests.fp_payload(uid uuid, sid text, n int, placement text, ctx text default 'training',
                                            battle text default null) returns jsonb
language sql as $$
  select jsonb_build_object(
    'userId', uid, 'receivedAt', now(), 'verified', true, 'verification', '{}'::jsonb,
    'signature', 'sig-' || sid,
    'log', case when battle is null then '{}'::jsonb
                else jsonb_build_object('context', jsonb_build_object('type', 'battle', 'battleId', battle)) end,
    'session', jsonb_build_object(
      'sessionId', sid, 'context', ctx, 'occurrenceId', null,
      'startedAt', (extract(epoch from now()) * 1000)::bigint - 60000, 'endedAt', (extract(epoch from now()) * 1000)::bigint,
      'ringAt', null, 'outcome', 'completed', 'snoozes', 0,
      'reps', (select jsonb_agg(jsonb_build_object('tStart', i * 2000, 'tEnd', i * 2000 + 1500, 'quality', 90))
                 from generate_series(0, n - 1) i),
      'specVersion', 2, 'appVersion', '0.1.0 (1)', 'platform', 'ios', 'bestSet', n, 'rejected', '{}'::jsonb,
      'placement', placement))
$$;

create temp table r1 as select app.apply_validated_session(tests.fp_payload((select a from ids),
  'f0000000-0000-4000-8000-000000000001', 12, 'front')) j;
select is((select placement from public.rep_sessions where id = 'f0000000-0000-4000-8000-000000000001'), 'front',
          'placement stored');
select is((select (j->>'competitive')::boolean from r1), false, 'front session is not competitive');
select is((select reps_total from public.user_stats_alltime where user_id = (select a from ids)), 12::bigint,
          'personal totals still count the reps');
select is((select coalesce(sum(reps_total), 0)::int from public.user_stats_daily where user_id = (select a from ids)), 0,
          'no leaderboard / clan war reps');

create temp table r2 as select app.apply_validated_session(tests.fp_payload((select a from ids),
  'f0000000-0000-4000-8000-000000000002', 10, 'side')) j;
select is((select (j->>'competitive')::boolean from r2), true, 'side session is competitive');
select is((select sum(reps_total)::int from public.user_stats_daily where user_id = (select a from ids)), 10,
          'side reps reach the leaderboards');

-- battles: a front session gives no battle reps
insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, start_at)
select 'b9000000-0000-4000-8000-000000000001', 'friendly', 'max_reps', '{"durationS": 60}', false, a, b, 'fa', 'fb', 'live',
       now() - interval '2 minutes' from ids;
insert into public.battle_events (battle_id, user_id, rep_index, t_end_server_ms, quality)
select 'b9000000-0000-4000-8000-000000000001', a, i, 1000 * i, 80 from ids, generate_series(1, 8) i;
select app.apply_validated_session(tests.fp_payload((select a from ids), 'f0000000-0000-4000-8000-000000000003', 8, 'front',
  'battle', 'b9000000-0000-4000-8000-000000000001'));
update public.rep_sessions set battle_id = 'b9000000-0000-4000-8000-000000000001'
 where id = 'f0000000-0000-4000-8000-000000000003';
select is((select flag from app.battle_reps((select b from public.battles b where id = 'b9000000-0000-4000-8000-000000000001'),
                                             (select a from ids))), 'front_placement', 'front battle session is flagged');
select is((select jsonb_array_length(reps) from app.battle_reps(
             (select b from public.battles b where id = 'b9000000-0000-4000-8000-000000000001'), (select a from ids))), 0,
          'and gives no battle reps');

select * from finish();
rollback;
