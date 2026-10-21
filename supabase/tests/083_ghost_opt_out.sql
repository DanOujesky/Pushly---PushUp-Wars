-- Ghost opt-out (privacy): opting out deletes recorded runs; the setting can be read back; only for yourself.
begin;
\ir _helpers.psql
select plan(6);

create temp table ids as select tests.create_user('go_a@example.com') a, tests.create_user('go_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
insert into public.ghost_runs (user_id, mode, variant, mmr_at, reps, timeline)
select u, 'max_reps', '{"durationS": 60}', 1500, 10, '[]' from ids, lateral (values (a), (b)) v(u);

select tests.authenticate_as((select a from ids));
select is(public.get_privacy_settings()->>'ghostOptOut', 'false', 'default: contributing');
select lives_ok($$ select public.set_ghost_opt_out(true) $$, 'opt out');
select is(public.get_privacy_settings()->>'ghostOptOut', 'true', 'setting stored');

select tests.as_owner();
select is((select count(*)::int from public.ghost_runs where user_id = (select a from ids)), 0, 'own runs deleted');
select is((select count(*)::int from public.ghost_runs where user_id = (select b from ids)), 1, 'others untouched');

select tests.as_anon();
select throws_ok($$ select public.get_privacy_settings() $$, '42501', null, 'anon cannot call');

select * from finish();
rollback;
