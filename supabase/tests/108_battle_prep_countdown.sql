-- Battle countdown gives 8 s to get ready (D-081).
begin;
\ir _helpers.psql
select plan(3);

create temp table ids as select tests.create_user('bp_a@example.com') a, tests.create_user('bp_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'bp_' || substr(p.id::text, 1, 6), onboarding_completed = true from ids where p.id in (ids.a, ids.b);
insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status)
select '00000000-0000-4000-8000-0000000000b1', 'friendly', 'max_reps', '{"durationS":60}', false, a, b, 'a', 'b', 'lobby' from ids;

select tests.authenticate_as((select a from ids));
select public.battle_ready('00000000-0000-4000-8000-0000000000b1');
select tests.authenticate_as((select b from ids));
select public.battle_ready('00000000-0000-4000-8000-0000000000b1');
select tests.as_owner();
select is((select status from public.battles where id = '00000000-0000-4000-8000-0000000000b1'), 'countdown', 'both ready → countdown');
select ok((select start_at between now() + interval '7.9 seconds' and now() + interval '8.1 seconds'
             from public.battles where id = '00000000-0000-4000-8000-0000000000b1'), 'starts 8 s later');

insert into public.battles (id, type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, start_at)
select '00000000-0000-4000-8000-0000000000b2', 'friendly', 'max_reps', '{"durationS":60}', false, a, b, 'a', 'b', 'countdown',
       now() - interval '30 seconds' from ids;
select ok((select start_at < now() from public.battles where id = '00000000-0000-4000-8000-0000000000b2'), 'a start in the past is kept');

select * from finish();
rollback;
