-- Clan War detail (D-079): per-clan fighters with points, raw push-ups, per-day numbers, zero-point members, members
-- who left; war history with MVP + contributors.
begin;
\ir _helpers.psql
select plan(14);

create temp table u as select n, tests.create_user('cwd_' || n || '@example.com') id from generate_series(1, 5) n;
grant select on u to authenticated, anon, service_role;
update public.profiles p set username = 'cwd_' || u.n, onboarding_completed = true, trust_score = 70 from u where p.id = u.id;
create or replace function tests.du(k int) returns uuid language sql as $$ select id from u where n = k $$;
create temp table wk as select app.war_week_start() + 7 as w;
grant select on wk to authenticated;

-- clan A: users 1 (leader), 2, 3 · clan B: users 4 (leader), 5
select tests.authenticate_as(tests.du(1));
select public.create_clan('Detail A', null, '{}', '', 'open');
select tests.authenticate_as(tests.du(4));
select public.create_clan('Detail B', null, '{}', '', 'open');
select tests.authenticate_as(tests.du(2));
select public.join_clan((select id from public.clans where name = 'Detail A'));
select tests.authenticate_as(tests.du(3));
select public.join_clan((select id from public.clans where name = 'Detail A'));
select tests.authenticate_as(tests.du(5));
select public.join_clan((select id from public.clans where name = 'Detail B'));

select tests.as_owner();
update public.clan_war_groups set week_start = (select w from wk);
select is(app.clan_war_start(app.war_starts_at((select w from wk)) + interval '5 minutes'), 1, 'the war starts');
create temp table war as select id from public.clan_war_groups where status = 'live';
grant select on war to authenticated, anon;

insert into public.user_stats_daily (user_id, day, reps_total) values
  (tests.du(1), (select w from wk), 50), (tests.du(1), (select w from wk) + 2, 30),
  (tests.du(2), (select w from wk) + 1, 120),
  (tests.du(4), (select w from wk), 40);

select tests.authenticate_as(tests.du(1));
create temp table d as select public.get_clan_war_detail((select id from war)) j;
grant select on d to authenticated;
select is(jsonb_array_length((select j from d)->'days'), 7, 'seven war days');
select is((select j from d)->'clans'->0->>'clanId', (select id::text from public.clans where name = 'Detail A'),
          'the leading clan first');
select is((select jsonb_agg(f->'user'->>'username') from d, jsonb_array_elements(j->'clans'->0->'fighters') f),
          '["cwd_2", "cwd_1", "cwd_3"]'::jsonb, 'fighters by points, the member with 0 listed last');
select is((select f->'days' from d, jsonb_array_elements(j->'clans'->0->'fighters') f where f->'user'->>'username' = 'cwd_1'),
          '[50, 0, 30, 0, 0, 0, 0]'::jsonb, 'points per war day');
select is((select (f->>'points')::int from d, jsonb_array_elements(j->'clans'->0->'fighters') f
            where f->'user'->>'username' = 'cwd_3'), 0, 'a member who did nothing shows 0');
select ok((select bool_and((f->>'inClan')::boolean) from d, jsonb_array_elements(j->'clans'->0->'fighters') f), 'all still in the clan');
select ok((select (j->'clans'->0->>'isMine')::boolean and not (j->'clans'->1->>'isMine')::boolean from d), 'my clan is marked');
select is((select jsonb_array_length(j->'clans'->1->'fighters') from d), 2, 'the rival clan''s fighters are listed too');
select is((select j->'war'->>'status' from d), 'live', 'with the war itself');

-- user 2 leaves: still listed with the points, inClan false
select tests.authenticate_as(tests.du(2));
select public.leave_clan();
select tests.authenticate_as(tests.du(1));
select is((select (f->>'inClan')::boolean from jsonb_array_elements(public.get_clan_war_detail((select id from war))->'clans'->0->'fighters') f
            where f->'user'->>'username' = 'cwd_2'), false, 'left the clan → still counted, marked');

-- results: MVP + contributors
select tests.as_owner();
select app.clan_war_tick(app.war_ends_at((select w from wk)));
select tests.authenticate_as(tests.du(1));
select is((public.get_clan_war_results()->0->>'contributors')::int, 2, 'two fighters scored for clan A');
select is(public.get_clan_war_results()->0->'mvp'->>'username', 'cwd_2', 'the MVP is in the history');

select throws_ok($$ select public.get_clan_war_detail(gen_random_uuid()) $$, 'P0002', null, 'unknown war');

select * from finish();
rollback;
