-- Battles end to end (P7-01/02/05/07 backend): invites, lifecycle, rep events, settlement with trophies + MMR,
-- caps, forfeits, matchmaking, seasons, battles board. Math details: generated 081_battle_vectors.sql.
begin;
\ir _helpers.psql
select plan(41);

create temp table ids as select tests.create_user('ba@example.com') a, tests.create_user('bb@example.com') b,
  tests.create_user('bc@example.com') c, tests.create_user('bd@example.com') d, tests.create_user('be@example.com') e,
  tests.create_user('bf@example.com') f;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = x.name, onboarding_completed = true, trust_score = x.trust
  from (select a id, 'bt_a' name, 70 trust from ids union all select b, 'bt_b', 70 from ids union all
        select c, 'bt_c', 70 from ids union all select d, 'bt_d', 70 from ids union all
        select e, 'bt_e', 70 from ids union all select f, 'bt_f', 20 from ids) x where p.id = x.id;
insert into public.friendships (user_a, user_b, status, requested_by) select least(a, b), greatest(a, b), 'accepted', a from ids;

-- invites ----------------------------------------------------------------------------------------
select tests.authenticate_as((select a from ids));
select throws_ok($$ select public.create_battle_invite((select c from ids), 'max_reps') $$, '42501', null, 'friends only');
select throws_ok($$ select public.create_battle_invite((select b from ids), 'max_reps', '{"durationS": 45}') $$, '22023', null,
                 'unknown variant');
select is(public.create_battle_invite(null, 'max_reps', '{}', true)->>'ranked', 'false', 'ranked flag ignored (D-071)');
create temp table inv as select public.create_battle_invite((select b from ids), 'max_reps', '{}', true) j;
grant select on inv to authenticated;
select is((select j->'variant' from inv), '{"durationS": 60}'::jsonb, 'default variant filled in');
select throws_ok($$ insert into public.battles (type, mode, ranked, player_a_name) values ('quick', 'speed', true, 'x') $$,
                 '42501', null, 'no direct battle inserts');

select tests.authenticate_as((select c from ids));
select throws_ok($$ select public.respond_battle_invite((select (j->>'id')::uuid from inv), true) $$, 'P0002', null,
                 'only the invited friend can accept');

select tests.authenticate_as((select b from ids));
select is(jsonb_array_length(public.list_battle_invites()->'incoming'), 1, 'b sees the invite');
create temp table bt as select public.respond_battle_invite((select (j->>'id')::uuid from inv), true) j;
grant select on bt to authenticated;
select is((select j->>'status' from bt), 'lobby', 'accepted → lobby');
select is((select j->>'type' from bt), 'friendly', 'friend battles are always friendly (D-071)');
-- the settlement below needs a ranked battle: make this one a quick match
select tests.as_owner();
update public.battles set type = 'quick', ranked = true where id = (select (j->>'id')::uuid from bt);
select tests.authenticate_as((select b from ids));
select is((select j->>'me' from bt), 'b', 'b is player b');

-- ready → countdown --------------------------------------------------------------------------------
select is(public.battle_ready((select (j->>'id')::uuid from bt))->>'status', 'ready_check', 'one ready');
select tests.authenticate_as((select a from ids));
select is(public.battle_ready((select (j->>'id')::uuid from bt))->>'status', 'countdown', 'both ready → countdown');
select throws_ok($$ select public.battle_push_rep((select (j->>'id')::uuid from bt), '[{"i":1,"t":500,"q":80}]') $$, 'P0001', null,
                 'no reps before the start');

-- live: pretend the battle started 70 s ago ---------------------------------------------------------
select tests.as_owner();
update public.battles set start_at = now() - interval '70 seconds' where id = (select (j->>'id')::uuid from bt);
select tests.authenticate_as((select a from ids));
select is(public.battle_push_rep((select (j->>'id')::uuid from bt),
          (select jsonb_agg(jsonb_build_object('i', i, 't', 1000 + i * 1500, 'q', 85)) from generate_series(1, 30) i)), 30,
          'a pushes 30 reps');
select is(public.battle_push_rep((select (j->>'id')::uuid from bt), '[{"i":1,"t":2500,"q":85}]'), 0, 'duplicates ignored');
select is(public.battle_push_rep((select (j->>'id')::uuid from bt), '[{"i":99,"t":90000,"q":85}]'), 0, 'reps from the future rejected');
select tests.authenticate_as((select b from ids));
select is(public.battle_push_rep((select (j->>'id')::uuid from bt),
          (select jsonb_agg(jsonb_build_object('i', i, 't', 1000 + i * 1600, 'q', 80)) from generate_series(1, 25) i)), 25,
          'b pushes 25 reps');
select is((public.get_battle((select (j->>'id')::uuid from bt))->'score'), '{"a": 30, "b": 25}'::jsonb, 'live score');
select tests.authenticate_as((select c from ids));
select throws_ok($$ select public.get_battle((select (j->>'id')::uuid from bt)) $$, 'P0002', null, 'outsiders cannot read a battle');
select is((select count(*)::int from public.battle_events), 0, 'outsiders see no events');

-- settle: both logs arrive (b's verified log counted only 20 reps → capped) --------------------------
select tests.as_owner();
insert into public.rep_sessions (id, user_id, context, battle_id, started_at, ended_at, reps_counted, spec_version, app_version, verified)
select gen_random_uuid(), u, 'battle', (select (j->>'id')::uuid from bt), now() - interval '70 seconds', now(), n, 1, 'x', true
  from ids, lateral (values (a, 30), (b, 20)) v(u, n);
select tests.authenticate_as((select a from ids));
create temp table fin as select public.battle_finish((select (j->>'id')::uuid from bt)) j;
grant select on fin to authenticated;
select is((select j->>'status' from fin), 'settled', 'settled when both logs are in');
select is((select j->>'winner' from fin), 'me', 'a won');
select is((select (j->'result'->'b'->>'reps')::int from fin), 20, 'b capped by the verified log');
select is((select (j->'result'->'trophies'->>'a')::int from fin), 45, 'placement win: 30 × 1.5');
select is((select (j->'result'->'trophies'->>'b')::int from fin), 0, 'placement loss at 0 trophies: floor 0');
select tests.as_owner();
select is((select trophies from public.profiles where id = (select a from ids)), 45, 'trophies written');
select ok((select mmr > 1600 from public.profiles where id = (select a from ids)), 'MMR went up');
select is((select count(*)::int from public.trophy_ledger), 2, 'ledger entries for both');

-- ranked friend cap: 3 counted per pair per day --------------------------------------------------------
insert into public.battles (type, mode, ranked, player_a, player_b, player_a_name, player_b_name, status, settled_at, result)
select 'friend_ranked', 'speed', true, a, b, 'x', 'y', 'settled', now(), '{"counted": true}' from ids, generate_series(1, 3);  -- legacy ranked friend battles (before D-071)
insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, start_at)
select 'b0000000-0000-4000-8000-000000000004', 'friend_ranked', 'max_reps', '{"durationS": 60}', true, a, b, 'x', 'y', 'live',
       now() - interval '200 seconds' from ids;
select ok(app.settle_battle('b0000000-0000-4000-8000-000000000004', false), 'timed-out battle settles without logs');
select is((select result->>'counted' from public.battles where id = 'b0000000-0000-4000-8000-000000000004'), 'false',
          '4th ranked battle of the day between the pair does not count');
select is((select result->'flags'->>'a' from public.battles where id = 'b0000000-0000-4000-8000-000000000004'), 'missing_log',
          'missing log flagged');

-- forfeit before the start = cancelled ------------------------------------------------------------
select tests.authenticate_as((select b from ids));
create temp table inv2 as select public.create_battle_invite((select a from ids), 'speed') j;
grant select on inv2 to authenticated;
select tests.authenticate_as((select a from ids));
create temp table bt2 as select public.respond_battle_invite((select (j->>'id')::uuid from inv2), true) j;
grant select on bt2 to authenticated;
select is(public.battle_forfeit((select (j->>'id')::uuid from bt2))->>'status', 'cancelled', 'leaving the lobby cancels');

-- matchmaking ---------------------------------------------------------------------------------------
select tests.authenticate_as((select d from ids));
select is((public.matchmaking_join('max_reps'))->>'queued', 'true', 'd waits');
select throws_ok($$ select public.matchmaking_join('turns') $$, '22023', null, 'turns is friend-only');
select tests.authenticate_as((select f from ids));
select is((public.matchmaking_join('max_reps'))->>'queued', 'true', 'low-trust f is not matched with d');
select tests.authenticate_as((select e from ids));
select is((public.matchmaking_join('max_reps'))->'battle'->>'type', 'quick', 'e is matched with d at once');
select tests.authenticate_as((select d from ids));
select is((public.matchmaking_status())->'battle'->'opponent'->>'username', 'bt_e', 'd gets the battle too');

-- seasons + battles board ------------------------------------------------------------------------
select tests.as_owner();
select ok(app.refresh_leaderboards() > 0, 'refresh');
select is((select score from public.leaderboard_snapshots where board = 'battles' and scope = 'global' and pos = 1), 45::bigint,
          'battles board by trophies');
insert into public.seasons (id, starts_at, ends_at, status) values (1, '2001-01-01', '2001-02-01', 'active');
update public.profiles set trophies = 3001, trophy_floor = 2000 where id = (select a from ids);
select is(app.rollover_season(), 1, 'rollover resets one player');
select is((select array[trophies, trophy_floor] from public.profiles where id = (select a from ids)), array[2500, 0],
          'soft reset above 2000, floors cleared');

select * from finish();
rollback;
