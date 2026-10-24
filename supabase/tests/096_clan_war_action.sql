-- Clan Wars with more fight (D-068): feed rows per gain, lead-change chat lines, days / theirTop / feed in the card,
-- rally with push + chat and a 6 h cooldown.
begin;
\ir _helpers.psql
select plan(13);

create temp table u as select n, tests.create_user('cwa' || n || '@example.com') id from generate_series(1, 4) n;
grant select on u to authenticated, anon, service_role;
update public.profiles p set username = 'cwa_' || u.n, onboarding_completed = true, trust_score = 70 from u where p.id = u.id;
create or replace function tests.cu(k int) returns uuid language sql as $$ select id from u where n = k $$;

insert into public.clans (id, name, tag, member_count) values
  ('c1000000-0000-4000-8000-000000000001', 'Red Dawn', 'RED', 2), ('c1000000-0000-4000-8000-000000000002', 'Blue Moon', 'BLU', 2);
insert into public.clan_members (clan_id, user_id, role) values
  ('c1000000-0000-4000-8000-000000000001', tests.cu(1), 'leader'), ('c1000000-0000-4000-8000-000000000001', tests.cu(2), 'member'),
  ('c1000000-0000-4000-8000-000000000002', tests.cu(3), 'leader'), ('c1000000-0000-4000-8000-000000000002', tests.cu(4), 'member');
insert into public.clan_wars (id, week_start, clan_a, clan_b) values
  ('d1000000-0000-4000-8000-000000000001', app.war_week_start(), 'c1000000-0000-4000-8000-000000000001',
   'c1000000-0000-4000-8000-000000000002');
insert into public.clan_war_rosters (war_id, clan_id, user_id)
select 'd1000000-0000-4000-8000-000000000001', m.clan_id, m.user_id from public.clan_members m;

insert into public.user_stats_daily (user_id, day, reps_total) values (tests.cu(1), (now() at time zone 'UTC')::date, 40);
select is((select points from public.clan_war_feed order by id desc limit 1), 40, 'a gain becomes a feed row');
select is((select count(*)::int from public.clan_messages where body like '%took the lead%'), 1, 'RED took the lead → chat line');
update public.user_stats_daily set reps_total = 60 where user_id = tests.cu(1);
select is((select points from public.clan_war_feed order by id desc limit 1), 20, 'later sessions add the difference');
insert into public.user_stats_daily (user_id, day, reps_total) values (tests.cu(3), (now() at time zone 'UTC')::date, 90);
select is((select count(*)::int from public.clan_messages where body like '%took the lead%'), 1,
          'lead changes are announced at most once an hour');

select tests.authenticate_as(tests.cu(2));
create temp table w as select public.get_clan_war() j;
grant select on w to authenticated;
select is((select (j->'score'->>'us')::int from w), 60, 'my clan''s score');
select is((select jsonb_array_length(j->'days') from w), 7, 'seven war days');
select is((select (j->'days'->(extract(isodow from now() at time zone 'UTC')::int - 1)->>'them')::int from w), 90,
          'today''s points per side');
select is((select j->'theirTop'->0->'user'->>'username' from w), 'cwa_3', 'the opponent''s best fighter');
select is((select j->'feed'->0->>'side' from w), 'them', 'newest feed entry first, with its side');
select is((select (j->'rally'->>'available')::boolean from w), true, 'rally available');

create temp table r as select public.clan_rally() j;
grant select on r to authenticated;
select tests.as_owner();
select is((select count(*)::int from public.push_outbox where type = 'clan_rally'), 1, 'push to the other member');
select tests.authenticate_as(tests.cu(1));
select throws_ok($$ select public.clan_rally() $$, 'P0001', null, 'one rally per clan every 6 hours');

select tests.as_anon();
select throws_ok($$ select public.clan_rally() $$, '42501', null, 'anon cannot rally');

select * from finish();
rollback;
