begin;
\ir _helpers.psql
select plan(26);

-- setup -----------------------------------------------------------------------
create temp table ids as
  select tests.create_user('ana@example.com') as ana, tests.create_user('tom@example.com') as tom;
grant select on ids to authenticated, anon, service_role;

select ok((select count(*) = 2 from public.profiles where id in ((select ana from ids), (select tom from ids))),
  'signup trigger creates a profile for each auth user');
select ok((select username::text ~ '^u_[0-9a-f]{12}$' from public.profiles where id = (select ana from ids)),
  'new profile gets a placeholder username');
select is((select onboarding_completed from public.profiles where id = (select ana from ids)), false,
  'onboarding is not completed after signup');
select lives_ok($$ insert into auth.users (id) values ('11111111-1111-4111-8111-abcdefabcdef'), ('22222222-2222-4222-8222-abcdefabcdef') $$,
  'placeholder username collisions are resolved (same uuid suffix)');

-- own row only ------------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select is((select count(*)::int from public.profiles), 1, 'user sees only their own profile row');
select is((select id from public.profiles), (select ana from ids), 'the visible row is their own');

-- direct writes are blocked -------------------------------------------------------
select throws_ok($$ update public.profiles set trophies = 9999 $$, '42501', null,
  'direct UPDATE on profiles is denied');
select throws_ok($$ insert into public.profiles (id, username) values (gen_random_uuid(), 'hacker') $$, '42501', null,
  'direct INSERT on profiles is denied');
select throws_ok($$ delete from public.profiles $$, '42501', null, 'direct DELETE on profiles is denied');

-- update_profile ------------------------------------------------------------------
select throws_ok($$ select public.update_profile('{"trophies": 5000}') $$, '22023', null,
  'update_profile rejects non-whitelisted fields');
select throws_ok($$ select public.update_profile('{"birth_year": 2015}') $$, '22023', 'minimum age is 16',
  'age gate rejects users under 16');
select throws_ok($$ select public.update_profile('{"username": "a!"}') $$, '22023', 'invalid username',
  'invalid username rejected');
select throws_ok($$ select public.update_profile('{"username": "u_0123456789ab"}') $$, '22023', 'username is reserved',
  'placeholder-shaped usernames are reserved (shared/test-vectors/account)');
select throws_ok($$ select public.update_profile('{"timezone": "Mars/Olympus"}') $$, '22023', 'unknown timezone',
  'unknown timezone rejected');
select throws_ok($$ select public.update_profile('{"avatar_path": "someone-else/avatar.jpg"}') $$, '42501', null,
  'avatar path must be in own folder');

select lives_ok($$ select public.update_profile('{"username": "AnaFit", "birth_year": 2000, "country": "cz", "timezone": "Europe/Prague"}') $$,
  'valid onboarding patch succeeds');
select is((select username::text from public.profiles), 'AnaFit', 'username updated');
select is((select country::text from public.profiles), 'CZ', 'country normalised to upper case');
select is((select onboarding_completed from public.profiles), true, 'onboarding completed after username + birth year');
select throws_ok($$ select public.update_profile('{"username": "AnaStrong"}') $$, 'P0001', null,
  'second username change within 30 days is rejected');

-- uniqueness is case-insensitive
select tests.authenticate_as((select tom from ids));
select is(public.username_available('anafit'), false, 'username_available is case-insensitive');
select is(public.username_available('TomPushes'), true, 'free username is available');
select throws_ok($$ select public.update_profile('{"username": "anafit"}') $$, '23505', null,
  'taken username (different case) is rejected');

-- public view ---------------------------------------------------------------------
select is((select count(*)::int from public.public_profiles where username = 'AnaFit'), 1,
  'other users see completed profiles through public_profiles');
select is((select count(*)::int from public.public_profiles where id = (select tom from ids)), 0,
  'profiles without completed onboarding are hidden from public_profiles');

-- anon ------------------------------------------------------------------------------
select tests.as_anon();
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon cannot read profiles');

select * from finish();
rollback;
