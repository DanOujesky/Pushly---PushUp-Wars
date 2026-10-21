-- Clans end to end (P8-01/03/05 backend): create, join flows, roles, chat, wars with caps, finalize.
begin;
\ir _helpers.psql
select plan(42);

create temp table u as
  select n, tests.create_user('clan' || n || '@example.com') id from generate_series(1, 12) n;
grant select on u to authenticated, anon, service_role;
update public.profiles p set username = 'cl_user' || u.n, onboarding_completed = true, trust_score = case when u.n = 6 then 40 else 70 end
  from u where p.id = u.id;
create or replace function tests.u(k int) returns uuid language sql as $$ select id from u where n = k $$;

-- create ---------------------------------------------------------------------------------------
select tests.authenticate_as(tests.u(1));
select throws_ok($$ select public.create_clan('Kurva Gang', 'KGNG') $$, '22023', null, 'profanity in names is refused');
select throws_ok($$ select public.create_clan('Iron Mornings', 'x!') $$, '22023', null, 'bad tag refused');
select is(public.create_clan('Iron Mornings', 'iron', '{}', 'Early birds', 'open')->>'myRole', 'leader', 'creator is leader');
select throws_ok($$ select public.create_clan('Second', 'SEC') $$, '22023', null, 'one clan per user');
select throws_ok($$ insert into public.clans (name, tag) values ('x', 'XXX') $$, '42501', null, 'no direct inserts');
select tests.authenticate_as(tests.u(7));
select throws_ok($$ select public.create_clan('iron mornings', 'IRN2') $$, '23505', null, 'names are unique case-insensitively');
create temp table c2 as select public.create_clan('Night Owls', 'OWL', '{}', '', 'request') j;
grant select on c2 to authenticated;
create temp table c1 as select id from public.clans where tag = 'IRON';
grant select on c1 to authenticated;

-- join flows -----------------------------------------------------------------------------------
select tests.authenticate_as(tests.u(2));
select is(public.join_clan((select id from c1)), 'joined', 'open clan: join at once');
select tests.authenticate_as(tests.u(8));
select is(public.join_clan((select (j->>'id')::uuid from c2), 'hi!'), 'requested', 'request clan: request');
select tests.authenticate_as(tests.u(7));
select is(jsonb_array_length(public.get_clan()->'requests'), 1, 'leader sees the request');
select is(public.respond_clan_request(tests.u(8), true), 'joined', 'accepted');
select tests.authenticate_as(tests.u(8));
select throws_ok($$ select public.respond_clan_request(tests.u(9), true) $$, '42501', null, 'members cannot accept requests');

do $$ begin
  perform tests.authenticate_as(tests.u(k)), public.join_clan((select id from c1)) from generate_series(3, 6) k;
end $$;
select tests.as_owner();
select is((select member_count from public.clans where tag = 'IRON'), 6::smallint, 'member count kept');
-- clan B: users 9..12 join through accepted requests
do $$
declare k int;
begin
  for k in 9..12 loop
    perform tests.authenticate_as(tests.u(k));
    perform public.join_clan((select (j->>'id')::uuid from c2));
    perform tests.authenticate_as(tests.u(7));
    perform public.respond_clan_request(tests.u(k), true);
  end loop;
end $$;
select tests.as_owner();
select is((select member_count from public.clans where tag = 'OWL'), 6::smallint, 'clan B has 6');

-- roles ----------------------------------------------------------------------------------------
select tests.authenticate_as(tests.u(1));
select lives_ok($$ select public.set_member_role(tests.u(2), 'co_leader') $$, 'leader promotes to co-leader');
select tests.authenticate_as(tests.u(2));
select throws_ok($$ select public.set_member_role(tests.u(3), 'co_leader') $$, '42501', null, 'co-leader can only promote to elder');
select lives_ok($$ select public.set_member_role(tests.u(3), 'elder') $$, 'co-leader promotes to elder');
select tests.authenticate_as(tests.u(3));
select throws_ok($$ select public.kick_member(tests.u(2)) $$, '42501', null, 'elder cannot kick a co-leader');
select tests.authenticate_as(tests.u(2));
select throws_ok($$ select public.kick_member(tests.u(1)) $$, '42501', null, 'nobody kicks the leader');

-- chat -----------------------------------------------------------------------------------------
select tests.authenticate_as(tests.u(4));
select ok((public.send_clan_message('Morning! you shit-hot people')->>'id') is not null, 'message sent');
select throws_ok($$ select public.send_clan_message('again') $$, 'P0001', null, '1 message per 2 seconds');
select is((select body from public.clan_messages where kind = 'text' order by id desc limit 1), 'Morning! you ****-hot people',
          'profanity masked');
select is((select count(*)::int from public.clan_messages where kind = 'text'), 1, 'members read their chat');
select tests.authenticate_as(tests.u(9));
select is((select count(*)::int from public.clan_messages where kind = 'text'), 0, 'other clans cannot read it');
select throws_ok($$ select public.send_clan_message('🙂', 'kudos') $$, '22023', null, 'only 👊 🔥 💪 reactions');

-- war: matchmake (both clans ≥ 5 members) ---------------------------------------------------------
select tests.as_owner();
select is(app.clan_war_matchmake('2026-10-19'), 1, 'one war');
select is((select count(*)::int from public.clan_war_rosters), 12, 'rosters frozen at start');
-- reps: u4 250 raw → 225 counted; u6 (trust 40) 100 → 50; u9 300 → 250
insert into public.user_stats_daily (user_id, day, reps_total) values
  (tests.u(4), '2026-10-20', 250), (tests.u(6), '2026-10-20', 100), (tests.u(9), '2026-10-21', 300);
select is((select array[score_a, score_b] from public.clan_wars), array[275, 250]::bigint[], 'caps + low-trust half applied');
update public.user_stats_daily set reps_total = 260 where user_id = tests.u(4);
select is((select score_a from public.clan_wars), 280::bigint, 'later sessions the same day add the capped difference');
insert into public.user_stats_daily (user_id, day, reps_total) values (tests.u(4), '2026-10-27', 50);
select is((select score_a from public.clan_wars), 280::bigint, 'reps after the war week do not count');

-- leaving keeps earlier reps, joining mid-war doesn't add ------------------------------------------
select tests.authenticate_as(tests.u(4));
select is(public.leave_clan(), 'left', 'u4 leaves');
select tests.as_owner();
select is((select score_a from public.clan_wars), 280::bigint, 'reps before leaving still count');
insert into public.user_stats_daily (user_id, day, reps_total) values (tests.u(4), '2026-10-22', 100);
select is((select score_a from public.clan_wars), 280::bigint, 'nothing after leaving');

select tests.authenticate_as(tests.u(1));
select is((public.get_clan_war()->'score'), '{"us": 280, "them": 250}'::jsonb, 'war card scores');
select is((public.get_clan_war()->'opponent'->>'tag'), 'OWL', 'war card opponent');

-- finalize -------------------------------------------------------------------------------------
select tests.as_owner();
select is(app.clan_war_finalize('2026-10-19'), 1, 'finalized');
select is((select winner from public.clan_wars), (select id from c1), 'higher score wins');
select is((select rating from public.clans where tag = 'IRON'), 1016, 'Elo +16 for an even match');
select is((select rating from public.clans where tag = 'OWL'), 984, 'Elo -16');
select is((select jsonb_array_length(result->'chests') from public.clan_wars), 3, 'chests for members with ≥ 50 counted reps');

-- leader leaving hands over; last member disbands -------------------------------------------------
select tests.authenticate_as(tests.u(1));
select is(public.leave_clan(), 'left', 'leader leaves');
select tests.as_owner();
select is((select p.username::text from public.clan_members m join public.profiles p on p.id = m.user_id
            join public.clans c on c.id = m.clan_id where c.tag = 'IRON' and m.role = 'leader'), 'cl_user2',
          'co-leader becomes leader');
select tests.authenticate_as(tests.u(10));
select is(jsonb_array_length(public.search_clans('iro')), 1, 'search by name');

select * from finish();
rollback;
