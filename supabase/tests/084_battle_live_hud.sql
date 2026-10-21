-- Live HUD data (migration 0020): Best of 3 rounds from the server clock, rest-time reps dropped, lastRepT, rounds.
begin;
\ir _helpers.psql
select plan(8);

create temp table ids as select tests.create_user('hud_a@example.com') a, tests.create_user('hud_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = case when p.id = (select a from ids) then 'hud_a' else 'hud_b' end,
       onboarding_completed = true where p.id in (select a from ids union select b from ids);

select tests.as_owner();
insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, start_at)
select 'b2000000-0000-4000-8000-000000000001', 'friendly', 'best_of_3', '{}', false, a, b, 'hud_a', 'hud_b', 'live',
       now() - interval '200 seconds' from ids;
insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, start_at)
select 'b2000000-0000-4000-8000-000000000002', 'friendly', 'turns', '{}', false, a, b, 'hud_a', 'hud_b', 'live',
       now() - interval '20 seconds' from ids;

select tests.authenticate_as((select a from ids));
-- round 0: 2 reps; 100 s is rest → dropped; 140 s and 141 s → round 1 even though the client says round 0
select is(public.battle_push_rep('b2000000-0000-4000-8000-000000000001',
  '[{"i":1,"t":1000,"q":80,"round":0},{"i":2,"t":2000,"q":80,"round":0},{"i":3,"t":100000,"q":80,"round":0},
    {"i":4,"t":140000,"q":80,"round":0},{"i":5,"t":141000,"q":80,"round":0}]'), 4, 'rest-time rep dropped');
select is((select array_agg(round_index order by rep_index) from public.battle_events
            where battle_id = 'b2000000-0000-4000-8000-000000000001'), array[0, 0, 1, 1]::smallint[], 'rounds from the clock');
select is(public.get_battle('b2000000-0000-4000-8000-000000000001')->'rounds',
          '[{"a": 2, "b": 0}, {"a": 2, "b": 0}, {"a": 0, "b": 0}]'::jsonb, 'rounds in get_battle');
select is((public.get_battle('b2000000-0000-4000-8000-000000000001')->'lastRepT'->>'a')::int, 141000, 'my last rep time');
select is(public.get_battle('b2000000-0000-4000-8000-000000000001')->'lastRepT'->'b', 'null'::jsonb, 'no reps yet → null');

-- turns: the opponent sees my last rep time and no rounds
select public.battle_push_rep('b2000000-0000-4000-8000-000000000002', '[{"i":1,"t":3000,"q":90}]');
select tests.authenticate_as((select b from ids));
select is((public.get_battle('b2000000-0000-4000-8000-000000000002')->'lastRepT'->>'a')::int, 3000, 'opponent last rep');
select is(public.get_battle('b2000000-0000-4000-8000-000000000002')->'rounds', 'null'::jsonb, 'no rounds outside best of 3');
select is((public.get_battle('b2000000-0000-4000-8000-000000000002')->'score'->>'a')::int, 1, 'score still counted');

select * from finish();
rollback;
