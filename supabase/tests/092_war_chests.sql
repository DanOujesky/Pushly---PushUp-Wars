-- War history + chests (migration 0021): chests granted on finalize, opened once for XP, history per clan, privacy.
begin;
\ir _helpers.psql
select plan(12);

create temp table ids as select tests.create_user('wc_a@example.com') a, tests.create_user('wc_b@example.com') b,
  tests.create_user('wc_c@example.com') c;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'wc_' || substr(p.id::text, 1, 6), onboarding_completed = true
 where p.id in (select a from ids union select b from ids union select c from ids);

select tests.as_owner();
insert into public.clans (id, name, tag) values ('c1000000-0000-4000-8000-000000000001', 'Chest Alpha', 'CHA'),
                                                ('c1000000-0000-4000-8000-000000000002', 'Chest Beta', 'CHB');
insert into public.clan_wars (id, week_start, clan_a, clan_b, score_a, score_b, status)
values ('d1000000-0000-4000-8000-000000000001', '2026-10-12', 'c1000000-0000-4000-8000-000000000001',
        'c1000000-0000-4000-8000-000000000002', 0, 0, 'live');
insert into public.clan_war_rosters (war_id, clan_id, user_id)
select 'd1000000-0000-4000-8000-000000000001'::uuid, 'c1000000-0000-4000-8000-000000000001'::uuid, a from ids union all
select 'd1000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000002', b from ids union all
select 'd1000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000002', c from ids;
insert into public.clan_war_member_daily (war_id, user_id, day, raw_reps, counted_reps)
select 'd1000000-0000-4000-8000-000000000001'::uuid, a, '2026-10-13'::date, 120, 120 from ids union all
select 'd1000000-0000-4000-8000-000000000001', b, '2026-10-13', 60, 60 from ids union all
select 'd1000000-0000-4000-8000-000000000001', c, '2026-10-13', 10, 10 from ids;
update public.clan_wars set score_a = 120, score_b = 70 where id = 'd1000000-0000-4000-8000-000000000001';
select is(app.clan_war_finalize('2026-10-12'), 1, 'finalized');
select is((select count(*)::int from public.user_chests), 2, 'two members qualified (≥ 50 reps)');
select is((select tier from public.user_chests where user_id = (select a from ids)), 'gold', 'winner → gold');
select is((select tier from public.user_chests where user_id = (select b from ids)), 'silver', 'loser → silver');

select tests.authenticate_as((select a from ids));
select is(jsonb_array_length(public.get_war_chests()->'unopened'), 1, 'one chest waiting');
select is((public.get_war_chests()->'medals'->>'gold')::int, 1, 'gold medal counted');
create temp table opened as select public.open_chest((select id from public.user_chests where user_id = (select a from ids))) j;
grant select on opened to authenticated;
select is((select (j->>'xp')::int from opened), 250, 'gold chest = 250 XP');
select throws_ok($$ select public.open_chest((select id from public.user_chests limit 1)) $$, 'P0002', null, 'opens only once');

select tests.authenticate_as((select b from ids));
select throws_ok($$ select public.open_chest((select id from public.user_chests where user_id = (select a from ids))) $$,
                 'P0002', null, 'cannot open someone else''s chest');
select is((select count(*)::int from public.user_chests where user_id = (select a from ids)), 0, 'others'' chests are private');
select is(public.get_clan_war_history('c1000000-0000-4000-8000-000000000001')->0->>'won', 'true', 'history: alpha won');
select is((public.get_clan_war_history('c1000000-0000-4000-8000-000000000002')->0->>'them')::int, 120, 'history from beta''s side');

select * from finish();
rollback;
