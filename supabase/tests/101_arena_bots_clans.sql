-- D-075: ranked Arena Bots after 10 s in the queue (steep trophy curve), clans without a typed tag, no War Chests.
begin;
\ir _helpers.psql
select plan(17);

create temp table ids as select tests.create_user('ab_a@example.com') a, tests.create_user('ab_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'ab_' || substr(p.id::text, 1, 6), onboarding_completed = true
 where p.id in (select a from ids union select b from ids);

-- the curve: easy at the start, brutal at the top
select is(app.arena_bot_reps(0), 10::double precision, 'bronze bot: 10 push-ups a minute');
select is(app.arena_bot_reps(4000), 52::double precision, 'champion line: 52');
select is(app.arena_bot_reps(5000), 75::double precision, 'legend line: 75');
select is(app.arena_bot_reps(9000), 88::double precision, 'flat after 6,000');
select ok(app.arena_bot_reps(1000) < app.arena_bot_reps(1001) or app.arena_bot_reps(1000) = app.arena_bot_reps(1001),
          'never easier with more trophies');
select ok((select bool_and(app.arena_bot_reps(t) <= app.arena_bot_reps(t + 50)) from generate_series(0, 7000, 50) t),
          'monotonic over the whole range');

-- matchmaking_bot: only after ~10 s in the queue
select tests.authenticate_as((select a from ids));
select public.matchmaking_join('max_reps');
select throws_ok($$ select public.matchmaking_bot() $$, 'P0001', null, 'too early: keep searching');
select tests.as_owner();
update public.matchmaking_queue set joined_at = now() - interval '11 seconds' where user_id = (select a from ids);
update public.profiles set trophies = 4000 where id = (select a from ids);
select tests.authenticate_as((select a from ids));
create temp table bb as select public.matchmaking_bot() j;
grant select on bb to authenticated, service_role;
select is((select (j->>'ranked')::boolean from bb), true, 'arena bot battles are ranked');
select is((select j->>'bot' from bb), 'arena', 'labelled as a bot');
select is((select j->'opponent'->>'username' from bb), 'Arena Bot', 'shown as Arena Bot, never as a person');
select ok((select jsonb_array_length(j->'ghostTimeline') between 44 and 60 from bb), 'champion-line bot: ~52 in a minute');
select tests.as_owner();
select is((select count(*)::int from public.matchmaking_queue where user_id = (select a from ids)), 0, 'left the queue');

-- no log from the player → the bot wins, trophies drop, ledger written, MMR untouched
select is(app.settle_battle((select (j->>'id')::uuid from bb), true), true, 'settled');
select ok((select trophies < 4000 from public.profiles where id = (select a from ids)), 'lost trophies to the bot');
select is((select mmr from public.profiles where id = (select a from ids)), 1500::double precision, 'MMR unchanged');

-- clans: no tag needed
select tests.authenticate_as((select b from ids));
select is(public.create_clan(name => 'Iron Mornings', description => 'early birds')->>'tag', 'IRONM', 'tag picked from the name');
select tests.as_owner();
select is((select count(*)::int from pg_trigger where tgname = 'clan_wars_chests'), 0, 'no War Chests trigger');

select * from finish();
rollback;
