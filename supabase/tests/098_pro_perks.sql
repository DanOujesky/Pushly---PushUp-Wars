-- Pushly Pro perks (D-073): unlimited ghost battles for Pro, the PRO flag on user cards.
begin;
\ir _helpers.psql
select plan(4);

create temp table ids as select tests.create_user('pp_a@example.com') a, tests.create_user('pp_b@example.com') b,
                                tests.create_user('pp_c@example.com') c;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'pp_' || substr(p.id::text, 1, 6), onboarding_completed = true
 where p.id in (select a from ids union select b from ids union select c from ids);
update public.profiles set is_pro = true where id = (select a from ids);
insert into public.ghost_runs (user_id, mode, variant, mmr_at, reps, timeline)
select c, 'max_reps', '{"durationS": 60}', 1500, 20,
       (select jsonb_agg(jsonb_build_object('t', 1000 + i * 2500, 'q', 80, 'round', 0) order by i) from generate_series(0, 19) i)
  from ids;

select tests.authenticate_as((select a from ids));
select public.start_ghost_battle('max_reps') from generate_series(1, 3);
select lives_ok($$ select public.start_ghost_battle('max_reps') $$, 'Pro: a 4th ghost battle today');

select tests.authenticate_as((select b from ids));
select public.start_ghost_battle('max_reps') from generate_series(1, 3);
select throws_ok($$ select public.start_ghost_battle('max_reps') $$, 'P0001', null, 'free: 3 a day');

select tests.as_owner();
select is((app.user_card((select a from ids), (select b from ids))->>'pro')::boolean, true, 'PRO flag on the card');
select is((app.user_card((select b from ids), (select a from ids))->>'pro')::boolean, false, 'free user: no flag');

select * from finish();
rollback;
