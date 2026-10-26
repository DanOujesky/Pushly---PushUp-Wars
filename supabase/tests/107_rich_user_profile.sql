-- Rich player profile (D-080): clan, battle record + form, rank, level, week numbers; hidden stats stay hidden.
begin;
\ir _helpers.psql
select plan(11);

create temp table ids as select tests.create_user('rp_a@example.com') a, tests.create_user('rp_b@example.com') b,
  tests.create_user('rp_c@example.com') c;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = x.n, onboarding_completed = true, profile_visibility = x.v::public.visibility_t,
       trophies = x.t, timezone = 'UTC'
  from (select a id, 'rp_a' n, 'public' v, 300 t from ids union all select b, 'rp_b', 'public', 500 from ids
        union all select c, 'rp_c', 'private', 0 from ids) x where p.id = x.id;
insert into public.battles (type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, result, settled_at)
select 'friendly', 'max_reps', '{"durationS":60}', false, a, b, 'rp_a', 'rp_b', 'settled', x.res::jsonb, now() - x.ago * interval '1 hour'
  from ids, (values ('{"winner":"a"}', 3), ('{"winner":"a"}', 2), ('{"winner":"b"}', 1)) x(res, ago);
insert into public.user_stats_daily (user_id, day, reps_total)
select a, (now() at time zone 'UTC')::date - k, 10 * (k + 1) from ids, generate_series(0, 8) k;

select tests.authenticate_as((select a from ids));
select public.create_clan('Profile Clan', null, '{}', 'hi', 'open');

select tests.authenticate_as((select c from ids));
create temp table pa as select public.get_user_profile((select a from ids)) j;
grant select on pa to authenticated;
select is((select j->'clan'->>'name' from pa), 'Profile Clan', 'the player''s clan');
select is((select j->'clan'->>'role' from pa), 'leader', 'with their role');
select is((select (j->'stats'->'battles'->>'wins')::int from pa), 2, 'battle wins');
select is((select (j->'stats'->'battles'->>'losses')::int from pa), 1, 'battle losses');
select is((select j->'stats'->'battles'->'form' from pa), '["L", "W", "W"]'::jsonb, 'form, newest first');
select is((select (j->'stats'->'battles'->>'bestWinStreak')::int from pa), 2, 'best win streak');
select is((select (j->'stats'->>'rank')::int from pa), 2, 'global rank by trophies');
select is((select j->'stats'->'last7' from pa), '[70, 60, 50, 40, 30, 20, 10]'::jsonb, 'last 7 days, oldest first');
select is((select (j->'stats'->>'repsWeek')::int from pa), 280, 'this week = last 7 days');

select tests.authenticate_as((select a from ids));
select is(public.get_user_profile((select c from ids))->'stats', 'null'::jsonb, 'private: no stats');
select is(public.get_user_profile((select c from ids))->'clan', 'null'::jsonb, 'no clan → null');

select * from finish();
rollback;
