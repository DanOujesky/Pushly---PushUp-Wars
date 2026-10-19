begin;
\ir _helpers.psql
select plan(8);

create temp table ids as
  select tests.create_user('ana@example.com') as ana, tests.create_user('tom@example.com') as tom;
grant select on ids to authenticated, anon, service_role;

insert into public.devices (user_id, platform, model) values
  ((select ana from ids), 'ios', 'iPhone15,2'),
  ((select tom from ids), 'android', 'Pixel 7');

-- devices --------------------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select is((select count(*)::int from public.devices), 1, 'user sees only own devices');
select is((select platform::text from public.devices), 'ios', 'and it is their device');
select throws_ok($$ insert into public.devices (user_id, platform) values (auth.uid(), 'ios') $$, '42501', null,
  'clients cannot register devices directly (Edge Function only)');
select throws_ok($$ update public.devices set push_token = 'x' $$, '42501', null, 'clients cannot update devices');

-- service role (Edge Functions) can write ----------------------------------------------
select tests.as_service();
select lives_ok($$ insert into public.devices (user_id, platform) select ana, 'android' from ids $$,
  'service role can register a device');

-- app_config -------------------------------------------------------------------------
select tests.as_anon();
select ok((select count(*) >= 1 from public.app_config), 'anon can read app_config (force-update check before login)');
select throws_ok($$ update public.app_config set value = '{}' $$, '42501', null, 'anon cannot modify app_config');
select tests.authenticate_as((select ana from ids));
select throws_ok($$ insert into public.app_config (key, value) values ('x', '{}') $$, '42501', null,
  'authenticated users cannot modify app_config');

select * from finish();
rollback;
