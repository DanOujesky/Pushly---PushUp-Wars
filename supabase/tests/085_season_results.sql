-- Season results (migration 0022): archived at rollover before the soft reset, best league, rank, privacy.
begin;
\ir _helpers.psql
select plan(8);

create temp table ids as select tests.create_user('se_a@example.com') a, tests.create_user('se_b@example.com') b,
  tests.create_user('se_c@example.com') c;
grant select on ids to authenticated, anon, service_role;

select tests.as_owner();
insert into public.seasons (id, starts_at, ends_at, status) values (1, '2001-01-01', '2001-02-01', 'active')
  on conflict (id) do update set status = 'active';
update public.profiles set trophies = 2400 where id = (select a from ids);
update public.profiles set trophies = 700 where id = (select b from ids);
insert into public.trophy_ledger (user_id, delta, balance_after, reason, season_id)
select a, 30, 2450, 'battle_win', 1 from ids union all
select a, -50, 2400, 'battle_loss', 1 from ids union all
select b, 30, 700, 'battle_win', 1 from ids;
select ok(app.rollover_season() >= 1, 'rollover ran');

select is((select count(*)::int from public.season_results where season_id = 1), 2, 'only players who battled');
select is((select array[final_trophies, best_trophies, rank] from public.season_results
            where season_id = 1 and user_id = (select a from ids)), array[2400, 2450, 1], 'final before reset, best, rank');
select is((select league || '/' || coalesce(tier, '') from public.season_results where season_id = 1 and user_id = (select a from ids)),
          'platinum/II', 'badge = best league reached');
select is((select trophies from public.profiles where id = (select a from ids)), 2200, 'soft reset still applied');

select tests.authenticate_as((select a from ids));
select is(jsonb_array_length(public.get_season_history()), 1, 'my history');
select is((select count(*)::int from public.season_results where user_id = (select b from ids)), 0, 'others are private');
select tests.authenticate_as((select c from ids));
select is(public.get_season_history(), '[]'::jsonb, 'no battles → no result');

select * from finish();
rollback;
