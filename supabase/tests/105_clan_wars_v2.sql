-- Clan Wars v2 lifecycle (D-078): lobby on creation, up to 4 per lobby, Monday start (lone clans merged or moved),
-- points, Sunday results with clan trophies, straight regroup into next week's lobbies, war off, read API, RLS.
begin;
\ir _helpers.psql
select plan(20);

create temp table u as select n, tests.create_user('cw2_' || n || '@example.com') id from generate_series(1, 6) n;
grant select on u to authenticated, anon, service_role;
update public.profiles p set username = 'cw2_' || u.n, onboarding_completed = true, trust_score = 70 from u where p.id = u.id;
create or replace function tests.wu(k int) returns uuid language sql as $$ select id from u where n = k $$;
create temp table wk as select app.war_week_start() + 7 as w;
grant select on wk to authenticated;
create or replace function tests.w() returns date language sql as $$ select w from wk $$;

-- five clans created mid-week: they fill one lobby of 4, the fifth opens a new one --------------------------------
do $$
declare k int;
begin
  for k in 1..5 loop
    perform tests.authenticate_as(tests.wu(k));
    perform public.create_clan('War Clan ' || k, null, '{}', '', 'open');
  end loop;
end $$;
select tests.as_owner();
select is((select count(*)::int from public.clan_war_entries where active), 5, 'every new clan is in a lobby at once');
select is((select array_agg(n order by n desc) from (select count(*)::int n from public.clan_war_entries group by group_id) x),
          array[4, 1], 'a lobby takes at most 4 clans');
select is((select count(*)::int from public.clan_war_groups where week_start = tests.w() and status = 'lobby'), 2,
          'lobbies are for next Monday');
select ok(exists (select 1 from public.clan_messages where body like '%joined our Clan War lobby%'), 'lobby members hear about newcomers');

-- Monday: the lone clan takes one clan from the group of 4 → 3 + 2, both live ---------------------------------------
select is(app.clan_war_start(app.war_starts_at(tests.w()) + interval '5 minutes'), 2, 'two wars start');
select is((select array_agg(n order by n desc) from (select count(*)::int n from public.clan_war_entries e
            join public.clan_war_groups g on g.id = e.group_id where g.status = 'live' group by e.group_id) x),
          array[3, 2], 'never a war of one: 4 + 1 becomes 3 + 2');
select ok((select bool_and(rating_before = 1000) from public.clan_war_entries), 'ratings frozen at the start');

-- a clan created after the start has nobody left this week → it waits for the next week -----------------------------
select tests.authenticate_as(tests.wu(6));
select ok((public.create_clan('Late Clan', null, '{}', '', 'open')->>'id') is not null, 'late clan created');
select tests.as_owner();
select app.clan_war_start(app.war_starts_at(tests.w()) + interval '10 minutes');
select is((select g.week_start from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
            join public.clans c on c.id = e.clan_id where c.name = 'Late Clan'), tests.w() + 7, 'alone → moved to next week');
select ok(exists (select 1 from public.clan_messages where body like 'No opponent was free this week%'), 'moved clans are told');

-- points + Sunday 20:00 UTC results, then straight into next week's lobbies ------------------------------------------
insert into public.user_stats_daily (user_id, day, reps_total)
select tests.wu(k), tests.w() + 1, 40 * k from generate_series(1, 5) k;
select ok((select sum(score) from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
            where g.status = 'live') = 600, 'points count for the live wars');
select app.clan_war_tick(app.war_ends_at(tests.w()));
select is((select count(*)::int from public.clan_war_groups where status = 'finished'), 2, 'both wars finished on Sunday');
select ok((select bool_and(rank is not null and rating_delta is not null) from public.clan_war_entries where not active),
          'ranks and clan trophies recorded');
select is((select sum(rating_delta)::int from public.clan_war_entries where not active), 0, 'clan trophies are zero-sum');
select is((select count(*)::int from public.clan_war_entries where active), 6, 'everyone is in a lobby again');
select is((select array_agg(n order by n) from (select count(*)::int n from public.clan_war_entries e
            join public.clan_war_groups g on g.id = e.group_id where e.active group by e.group_id) x),
          array[3, 3], 'regrouped evenly (6 → 3 + 3), the lone clan included');

-- read API ----------------------------------------------------------------------------------------------------------
select tests.authenticate_as(tests.wu(5));
select is(public.get_clan_war_state()->'last'->>'status', 'finished', 'last war = the result screen');
select is(public.get_clan_war_state()->'current'->>'status', 'lobby', 'current = next lobby');
select throws_ok($$ select * from public.clan_war_entries $$, '42501', null, 'no direct table access');

-- war switched off: out of the lobby -------------------------------------------------------------------------------
select tests.as_owner();
update public.clans set war_enabled = false where name = 'Late Clan';
select is((select count(*)::int from public.clan_war_entries e join public.clans c on c.id = e.clan_id
            where c.name = 'Late Clan' and e.active), 0, 'war off → leaves the lobby');

select * from finish();
rollback;
