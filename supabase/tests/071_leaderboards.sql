-- Leaderboards (P6-03, doc 08 §4): eligibility, ties, scopes, anonymous rows, shadow mode, snapshots; push quiet hours.
begin;
\ir _helpers.psql
select plan(22);

create temp table ids as select tests.create_user('a@example.com') a, tests.create_user('b@example.com') b,
  tests.create_user('c@example.com') c, tests.create_user('d@example.com') d, tests.create_user('e@example.com') e;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = x.name, onboarding_completed = true, country = x.cc, trust_score = x.trust,
                            leaderboard_visible = x.vis
  from (select a id, 'lb_a' name, 'CZ' cc, 70 trust, true vis from ids union all
        select b, 'lb_b', 'CZ', 70, false from ids union all     -- hidden → anonymous row
        select c, 'lb_c', 'DE', 70, true from ids union all
        select d, 'lb_d', 'CZ', 30, true from ids union all      -- low trust → not listed (shadow)
        select e, 'lb_e', null, 70, true from ids) x
 where p.id = x.id;

insert into public.user_stats_weekly (user_id, week_start, reps_total, wake_points)
select u, date_trunc('week', now() at time zone 'UTC')::date, r, w from ids,
  lateral (values (a, 100, 30), (b, 300, 30), (c, 200, 10), (d, 999, 99), (e, 50, 5)) v(u, r, w);
insert into public.streaks (user_id, current, best, pure_current, pure_best)
select u, pc, pb, pc, pb from ids, lateral (values (a, 5, 9), (b, 5, 12), (c, 2, 2)) v(u, pc, pb);
insert into public.friendships (user_a, user_b, status, requested_by)
select least(a, e), greatest(a, e), 'accepted', a from ids;

select is(app.period_key('week', '2026-10-21T10:00:00Z'), '2026-W43', 'ISO week key');
select is(app.period_key('day', '2026-10-20T23:59:59Z'), '2026-10-20', 'UTC day key');
select is(app.period_key('month', '2026-10-31T23:00:00Z'), '2026-10', 'UTC month key');

select ok(app.refresh_leaderboards() > 0, 'snapshots refreshed');
select is((select array_agg(username order by s.pos) from public.leaderboard_snapshots s join public.profiles p on p.id = s.user_id
            where board = 'reps' and scope = 'global' and period_key = app.period_key('week')),
          array['lb_b', 'lb_c', 'lb_a', 'lb_e']::citext[], 'low-trust user is not on the board');
select is((select array_agg(rank order by pos) from public.leaderboard_snapshots
            where board = 'wake' and scope = 'global' and period_key = app.period_key('week')),
          array[1, 1, 3, 4], 'equal scores share a rank');
select is((select array_agg(rank order by pos) from public.leaderboard_snapshots
            where board = 'streak' and scope = 'global'),
          array[1, 2, 3], 'streak ties broken by the longer best streak');

select tests.authenticate_as((select a from ids));
select throws_ok($$ select * from public.leaderboard_snapshots $$, '42501', null, 'snapshots only via the RPC');
create temp table g as select public.get_leaderboard('reps', 'global', 'week') j;
grant select on g to authenticated;
select is((select jsonb_array_length(j->'rows') from g), 4, 'four rows');
select is((select j->'rows'->0->'user'->>'anonymous' from g), 'true', 'hidden user shows as anonymous');
select is((select j->'rows'->0->'user'->>'id' from g), null, 'anonymous rows carry no id');
select is((select (j->'rows'->2->>'isMe')::boolean from g), true, 'own row flagged');
select is((select (j->'me'->>'rank')::int from g), 3, 'my rank');
select is((select (j->'me'->>'shadow')::boolean from g), false, 'eligible, no shadow');

select is((select jsonb_agg(r->'user'->>'username') from jsonb_array_elements(public.get_leaderboard('reps', 'country', 'week')->'rows') r),
          '[null, "lb_a"]'::jsonb, 'country board: CZ only, low trust excluded');
select is((select jsonb_agg(r->'user'->>'username') from jsonb_array_elements(public.get_leaderboard('reps', 'friends', 'week')->'rows') r),
          '["lb_a", "lb_e"]'::jsonb, 'friends board: me + friends');
select throws_ok($$ select public.get_leaderboard('reps', 'global', 'season') $$, '22023', null, 'unknown period');

select tests.authenticate_as((select d from ids));
select is((public.get_leaderboard('reps', 'global', 'week')->'me'->>'shadow')::boolean, true, 'low-trust user is in shadow mode');
select is((public.get_leaderboard('reps', 'global', 'week')->'me'->>'rank')::int, 1, 'and sees a would-be rank');

select tests.authenticate_as((select e from ids));
select is(public.get_leaderboard('reps', 'country', 'week')->>'needsCountry', 'true', 'no country set → prompt');

-- push quiet hours: held until the window ends -------------------------------------------------
select tests.as_owner();
update public.profiles set timezone = 'UTC' where id = (select a from ids);
insert into public.notification_prefs (user_id, prefs) select a, jsonb_build_object(
  'quietStart', to_char((now() at time zone 'UTC') - interval '1 hour', 'HH24:MI'),
  'quietEnd', to_char((now() at time zone 'UTC') + interval '1 hour', 'HH24:MI')) from ids;
select app.enqueue_push((select a from ids), 'test', 'social', '{}');
select ok((select send_after > now() + interval '50 minutes' from public.push_outbox where type = 'test'),
          'non-alarm push waits for the end of quiet hours');
select app.enqueue_push((select a from ids), 'alarm_test', 'alarm', '{}');
select ok((select send_after <= now() from public.push_outbox where type = 'alarm_test'), 'alarm pushes ignore quiet hours');

select * from finish();
rollback;
