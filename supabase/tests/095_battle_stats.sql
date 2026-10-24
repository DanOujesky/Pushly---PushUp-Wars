-- Trophy-first stats (D-067): league + next step, live rank, record with streaks, history, recent battles, targets.
begin;
\ir _helpers.psql
select plan(12);

create temp table ids as select tests.create_user('bs_a@example.com') a, tests.create_user('bs_b@example.com') b,
                                tests.create_user('bs_c@example.com') c;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'bs_' || substr(p.id::text, 1, 6), onboarding_completed = true
 where p.id in (select a from ids union select b from ids union select c from ids);
update public.profiles set trophies = 450, best_trophies = 500, win_streak = 1 where id = (select a from ids);
update public.profiles set trophies = 470 where id = (select b from ids);
update public.profiles set trophies = 900 where id = (select c from ids);

-- three settled battles a vs b: win, loss, win (a is player_a)
insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status,
                            start_at, settled_at, result)
select ('b5000000-0000-4000-8000-00000000000' || i)::uuid, 'quick', 'max_reps', '{"durationS": 60}', true, a, b, 'me', 'rival',
       'settled', now() - (10 - i) * interval '1 hour', now() - (10 - i) * interval '1 hour',
       jsonb_build_object('winner', case when i = 2 then 'b' else 'a' end, 'reason', 'reps',
                          'trophies', jsonb_build_object('a', case when i = 2 then -20 else 30 end, 'b', 0))
  from ids, generate_series(1, 3) i;
insert into public.trophy_ledger (user_id, battle_id, delta, balance_after, reason)
select a, ('b5000000-0000-4000-8000-00000000000' || i)::uuid, 30, 400 + i * 10, 'battle_win' from ids, generate_series(1, 3) i;

select tests.authenticate_as((select a from ids));
create temp table s as select public.get_battle_stats() j;
grant select on s to authenticated;
select is((select j->>'league' from s), 'bronze', 'league from trophies');
select is((select j->>'tier' from s), 'I', 'tier');
select is((select (j->'next'->>'at')::int from s), 600, 'next step: silver at 600');
select is((select j->'next'->>'league' from s), 'silver', 'next league');
select is((select (j->>'rank')::int from s), 3, 'live rank: two players have more trophies');
select is((select (j->'record'->>'wins')::int from s), 2, 'wins');
select is((select (j->'record'->>'losses')::int from s), 1, 'losses');
select is((select (j->'record'->>'bestWinStreak')::int from s), 1, 'best streak from the order of results');
select is((select jsonb_array_length(j->'history') from s), 4, 'history: start point + 3 changes');
select is((select j->'recent'->0->>'result' from s), 'win', 'newest battle first');
select is((select j->'targets'->0->>'gap' from s), '20', 'closest player above first, with the gap');

select tests.as_anon();
select throws_ok($$ select public.get_battle_stats() $$, '42501', null, 'anon cannot call');

select * from finish();
rollback;
