-- Friend battles are always friendly (D-071): the ranked flag of an invite is ignored, so accepting never creates a
-- trophy battle.
begin;
\ir _helpers.psql
select plan(4);

create temp table ids as select tests.create_user('ff_a@example.com') a, tests.create_user('ff_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'ff_' || substr(p.id::text, 1, 6), onboarding_completed = true
 where p.id in (select a from ids union select b from ids);
insert into public.friendships (user_a, user_b, status, requested_by) select least(a, b), greatest(a, b), 'accepted', a from ids;

select tests.authenticate_as((select a from ids));
create temp table inv as select public.create_battle_invite((select b from ids), 'speed', '{}', true) j;
grant select on inv to authenticated;
select is((select j->>'ranked' from inv), 'false', 'invite stored as friendly even when ranked is asked');

select tests.authenticate_as((select b from ids));
create temp table bt as select public.respond_battle_invite((select (j->>'id')::uuid from inv), true) j;
grant select on bt to authenticated;
select is((select j->>'type' from bt), 'friendly', 'accepted → friendly battle');
select is((select (j->>'ranked')::boolean from bt), false, 'not ranked');
select tests.as_owner();
select is((select count(*)::int from public.battle_invites where ranked), 0, 'no ranked invites exist');

select * from finish();
rollback;
