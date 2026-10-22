-- Practice bots (D-063): labelled bot opponents, level by MMR, timelines per mode, ghost fallback, never ranked,
-- bots don't use up the ghost limit, bot runs never become someone's ghost.
begin;
\ir _helpers.psql
select plan(16);

create temp table ids as select tests.create_user('bot_a@example.com') a;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'bot_a', onboarding_completed = true where p.id = (select a from ids);

select tests.authenticate_as((select a from ids));
create temp table b1 as select public.start_bot_battle('max_reps') j;
grant select on b1 to authenticated;
select is((select j->>'bot' from b1), 'rookie', 'a new player (MMR 1500) gets a rookie bot');
select is((select j->'opponent'->>'username' from b1), 'Bot · Rookie', 'the bot is labelled as a bot');
select is((select (j->>'ranked')::boolean from b1), false, 'never ranked');
select is((select j->>'type' from b1), 'ghost', 'runs on the ghost machinery');
select ok((select jsonb_array_length(j->'ghostTimeline') between 15 and 30 from b1), 'rookie: ~23 reps in 60 s');
select ok((select bool_and((r->>'t')::bigint < 60000) from b1, jsonb_array_elements(j->'ghostTimeline') r),
          'every rep inside the minute');

create temp table b2 as select public.start_bot_battle('speed', 'champion') j;
grant select on b2 to authenticated;
select is((select jsonb_array_length(j->'ghostTimeline') from b2), 20, 'speed: exactly the target');
select is((select j->'opponent'->>'username' from b2), 'Bot · Champion', 'chosen level');

create temp table b3 as select public.start_bot_battle('best_of_3', 'pro') j;
grant select on b3 to authenticated;
select tests.as_owner();
select ok((select bool_and(app.bo3_in_window((r->>'t')::bigint) and app.bo3_round((r->>'t')::bigint) = (r->>'round')::int)
             from b3, jsonb_array_elements(j->'ghostTimeline') r), 'best of 3: reps only inside the round windows');
select is((select count(distinct r->>'round')::int from b3, jsonb_array_elements(j->'ghostTimeline') r), 3, 'three rounds');
select tests.authenticate_as((select a from ids));

select throws_ok($$ select public.start_bot_battle('turns') $$, '22023', null, 'turns is not a bot mode');
select throws_ok($$ select public.start_bot_battle('max_reps', 'godlike') $$, '22023', null, 'unknown level refused');

-- no human ghost exists → ghost battle falls back to a bot; bots don't use up the 3 daily ghost battles
create temp table g as select public.start_ghost_battle('max_reps') j;
grant select on g to authenticated;
select is((select j->>'bot' from g), 'rookie', 'ghost fallback is a labelled bot');
select lives_ok($$ select public.start_ghost_battle('max_reps'); select public.start_ghost_battle('max_reps');
                   select public.start_ghost_battle('max_reps') $$, 'bot battles do not count toward the ghost limit');

-- a bot battle is settled on the player's log like any ghost; bot runs never become a human's ghost
select tests.as_owner();
select is((select count(*)::int from public.ghost_runs where user_id is null and bot_level is null), 0,
          'every run has an owner or a bot level');
select tests.as_anon();
select throws_ok($$ select public.start_bot_battle('max_reps') $$, '42501', null, 'anon cannot start a bot battle');

select * from finish();
rollback;
