-- Ghost battles (P7-03): picking a ghost, live ghost score, settlement on the player's log, daily limit; battles are no longer recorded (D-076).
begin;
\ir _helpers.psql
select plan(13);

create temp table ids as select tests.create_user('gh_a@example.com') a, tests.create_user('gh_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = case when p.id = (select a from ids) then 'gh_a' else 'gh_b' end,
       onboarding_completed = true where p.id in (select a from ids union select b from ids);
insert into public.ghost_runs (user_id, mode, variant, mmr_at, reps, timeline)
select b, 'max_reps', '{"durationS": 60}', 1500, 20,
       (select jsonb_agg(jsonb_build_object('t', 1000 + i * 2500, 'q', 80, 'round', 0) order by i) from generate_series(0, 19) i)
  from ids;

select tests.authenticate_as((select a from ids));
select throws_ok($$ select * from public.ghost_runs $$, '42501', null, 'ghost runs are private');
select throws_ok($$ select public.start_ghost_battle('max_reps', true) $$, 'P0002', null, 'no own best yet');
create temp table g as select public.start_ghost_battle('max_reps') j;
grant select on g to authenticated;
select is((select j->>'type' from g), 'ghost', 'ghost battle');
select is((select j->'opponent'->>'username' from g), 'Ghost', 'strangers stay anonymous');
select is((select j->>'status' from g), 'countdown', 'starts right away');
select is((select jsonb_array_length(j->'ghostTimeline') from g), 20, 'timeline for the on-screen ghost');

select tests.as_owner();
update public.battles set start_at = now() - interval '26 seconds' where id = (select (j->>'id')::uuid from g);
select tests.authenticate_as((select a from ids));
select is((public.get_battle((select (j->>'id')::uuid from g))->'score'->>'b')::int, 11, 'live ghost score follows the clock');
select is(public.battle_push_rep((select (j->>'id')::uuid from g),
          (select jsonb_agg(jsonb_build_object('i', i, 't', 500 + i * 1000, 'q', 85)) from generate_series(1, 25) i)), 25, 'reps in');

-- the player's log arrives → settled at once
select tests.as_owner();
insert into public.rep_sessions (id, user_id, context, started_at, ended_at, reps_counted, spec_version, app_version, verified)
values ('c0000000-0000-4000-8000-000000000001', (select a from ids), 'battle', now() - interval '30 seconds', now(), 25, 1, 'x', true);
insert into public.rep_session_logs (session_id, log, signature)
select 'c0000000-0000-4000-8000-000000000001', jsonb_build_object('context', jsonb_build_object('type', 'battle',
       'battleId', (select j->>'id' from g))), 'sig-ghost';
select is((select status::text from public.battles where id = (select (j->>'id')::uuid from g)), 'settled', 'settled on the log');
select tests.authenticate_as((select a from ids));
select is(public.get_battle((select (j->>'id')::uuid from g))->>'winner', 'me', '25 beat the ghost''s 20');
select is((public.get_battle((select (j->>'id')::uuid from g))->'result'->>'counted')::boolean, false, 'never ranked');

-- limit: 3 a day for free users
select public.start_ghost_battle('max_reps');
select public.start_ghost_battle('max_reps');
select throws_ok($$ select public.start_ghost_battle('max_reps') $$, 'P0001', null, 'fourth ghost battle today refused');

-- settled human battles no longer become ghost runs (D-076)
select tests.as_owner();
insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, start_at)
select 'b1000000-0000-4000-8000-000000000001', 'friendly', 'speed', '{"targetReps": 20}', false, a, b, 'gh_a', 'gh_b', 'live',
       now() - interval '200 seconds' from ids;
insert into public.battle_events (battle_id, user_id, rep_index, t_end_server_ms, quality)
select 'b1000000-0000-4000-8000-000000000001', b, i, 1000 * i, 80 from ids, generate_series(1, 8) i;
insert into public.rep_sessions (id, user_id, context, battle_id, started_at, ended_at, reps_counted, spec_version, app_version, verified)
select 'c0000000-0000-4000-8000-000000000002', b, 'battle', 'b1000000-0000-4000-8000-000000000001', now(), now(), 8, 1, 'x', true from ids;
select app.settle_battle('b1000000-0000-4000-8000-000000000001', true);
select is((select count(*)::int from public.ghost_runs where mode = 'speed'), 0, 'battles are not recorded as ghosts any more');

select * from finish();
rollback;
