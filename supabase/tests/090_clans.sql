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

-- war v2 (D-078): both clans share a lobby as soon as they exist; Monday → live ------------------------
select tests.as_owner();
select is((select count(distinct group_id)::int from public.clan_war_entries where active), 1, 'both clans in one lobby');
update public.clan_war_groups set week_start = '2026-10-19';
select is(app.clan_war_start('2026-10-19 00:05+00'), 1, 'the lobby goes live on Monday');
-- reps: u4 250 raw → 225 counted; u6 (trust 40) 100 → 50; u9 300 → 250
insert into public.user_stats_daily (user_id, day, reps_total) values
  (tests.u(4), '2026-10-20', 250), (tests.u(6), '2026-10-20', 100), (tests.u(9), '2026-10-21', 300);
create or replace function tests.scores() returns bigint[] language sql as $$
  select array_agg(e.score order by c.tag) from public.clan_war_entries e join public.clans c on c.id = e.clan_id $$;
select is(tests.scores(), array[275, 250]::bigint[], 'caps + low-trust half applied');
update public.user_stats_daily set reps_total = 260 where user_id = tests.u(4);
select is(tests.scores(), array[280, 250]::bigint[], 'later sessions the same day add the capped difference');
insert into public.user_stats_daily (user_id, day, reps_total) values (tests.u(4), '2026-10-27', 50);
select is(tests.scores(), array[280, 250]::bigint[], 'reps after the war week do not count');

-- leaving keeps earlier reps, after leaving nothing counts for the old clan ------------------------------
select tests.authenticate_as(tests.u(4));
select is(public.leave_clan(), 'left', 'u4 leaves');
select tests.as_owner();
select is(tests.scores(), array[280, 250]::bigint[], 'reps before leaving still count');
insert into public.user_stats_daily (user_id, day, reps_total) values (tests.u(4), '2026-10-22', 100);
select is(tests.scores(), array[280, 250]::bigint[], 'nothing after leaving');

select tests.authenticate_as(tests.u(1));
select is((select (c->>'score')::int from jsonb_array_elements(public.get_clan_war_state()->'current'->'clans') c
            where (c->>'isMine')::boolean), 280, 'war state: my score');
select is((select c->'clan'->>'tag' from jsonb_array_elements(public.get_clan_war_state()->'current'->'clans') c
            where not (c->>'isMine')::boolean), 'OWL', 'war state: the opponent');

-- Sunday 20:00 UTC: results ------------------------------------------------------------------------------
select tests.as_owner();
select is(app.clan_war_finish('2026-10-25 20:00+00'), 1, 'finished');
select is((select e.rank from public.clan_war_entries e join public.clans c on c.id = e.clan_id where c.tag = 'IRON'), 1,
          'higher score wins');
select is((select rating from public.clans where tag = 'IRON'), 1015, 'clan trophies +15 for an even duel');
select is((select rating from public.clans where tag = 'OWL'), 985, 'clan trophies -15');
select ok((select mvp from public.clan_war_entries e join public.clans c on c.id = e.clan_id where c.tag = 'OWL') = tests.u(9),
          'MVP recorded');

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
