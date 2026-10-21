-- Player profiles (migration 0023): visibility, relation, head-to-head, blocks look like not found.
begin;
\ir _helpers.psql
select plan(10);

create temp table ids as select tests.create_user('up_a@example.com') a, tests.create_user('up_b@example.com') b,
  tests.create_user('up_c@example.com') c;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = x.n, onboarding_completed = true, profile_visibility = x.v::public.visibility_t
  from (select a id, 'up_a' n, 'public' v from ids union all select b, 'up_b', 'friends' from ids
        union all select c, 'up_c', 'private' from ids) x where p.id = x.id;
insert into public.friendships (user_a, user_b, status, requested_by) select least(a, b), greatest(a, b), 'accepted', a from ids;
insert into public.battles (type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, result)
select 'friendly', 'max_reps', '{"durationS":60}', false, a, b, 'up_a', 'up_b', 'settled', '{"winner":"a","reason":"reps"}' from ids;

select tests.authenticate_as((select a from ids));
select is(public.get_user_profile((select b from ids))->>'relation', 'friends', 'friends');
select is(public.get_user_profile((select b from ids))->>'visible', 'true', 'friends-only profile visible to a friend');
select is((public.get_user_profile((select b from ids))->'headToHead'->>'wins')::int, 1, 'head to head');
select is(public.get_user_profile(null, 'up_c')->>'visible', 'false', 'private profile hidden');
select is(public.get_user_profile(null, 'up_c')->'stats', 'null'::jsonb, 'no stats when hidden');
select is(public.get_user_profile((select a from ids))->>'relation', 'self', 'own profile');

select tests.authenticate_as((select c from ids));
select is(public.get_user_profile((select b from ids))->>'visible', 'false', 'friends-only hidden to strangers');
select is(public.get_user_profile((select a from ids))->>'visible', 'true', 'public visible to everyone');
select public.block_user((select a from ids));
select tests.authenticate_as((select a from ids));
select is(public.get_user_profile((select c from ids)), null, 'blocked → not found (no leak)');
select is(public.get_user_profile(null, 'nobody_here'), null, 'unknown user');

select * from finish();
rollback;
