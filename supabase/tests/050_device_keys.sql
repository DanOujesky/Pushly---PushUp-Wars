-- Device keys (P4-02 part 1): registration is idempotent, per user, validated, capped.
begin;
\ir _helpers.psql
select plan(8);

create temp table ids as select tests.create_user('ana@example.com') as ana, tests.create_user('tom@example.com') as tom;
grant select on ids to authenticated, anon, service_role;
create or replace function tests.key(n int) returns text language sql as
$$ select rpad('MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE' || n::text, 124, 'A') $$;

select tests.authenticate_as((select ana from ids));
create temp table r as select public.register_device(jsonb_build_object('platform', 'ios', 'publicKey', tests.key(1),
  'model', 'iPhone17,1', 'osVersion', '26.0', 'appVersion', '0.1.0 (8)')) as id;
grant select on r to authenticated, anon, service_role;
select is((select count(*)::int from public.devices), 1, 'device registered');
select is(public.register_device(jsonb_build_object('platform', 'ios', 'publicKey', tests.key(1))), (select id from r),
          'registering the same key again returns the same device');
select throws_ok($$ select public.register_device('{"platform":"ios","publicKey":"short"}') $$, '22023', null,
                 'malformed keys are rejected');
select throws_ok($$ select public.register_device('{"platform":"windows","publicKey":"x"}') $$, '22023', null,
                 'unknown platforms are rejected');
select lives_ok($$ select public.register_device(jsonb_build_object('platform', 'android', 'publicKey', tests.key(n)))
                   from generate_series(2, 11) n $$, 'more devices');
select is((select count(*)::int from public.devices where revoked_at is null), 10, 'at most 10 active devices per user');

select tests.authenticate_as((select tom from ids));
select is((select count(*)::int from public.devices), 0, 'Tom does not see Ana''s devices');
select tests.as_anon();
select throws_ok($$ select public.register_device('{}') $$, '42501', null, 'anon cannot register devices');

select * from finish();
rollback;
