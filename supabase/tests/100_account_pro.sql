-- Reports, data export, account deletion, Pro entitlements (P9-03, P10-01 server side).
begin;
\ir _helpers.psql
select plan(19);

create temp table ids as select tests.create_user('acc_a@example.com') a, tests.create_user('acc_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = case when p.id = (select a from ids) then 'acc_a' else 'acc_b' end, onboarding_completed = true
 where p.id in (select a from ids union select b from ids);

-- reports ---------------------------------------------------------------------------------------
select tests.authenticate_as((select a from ids));
select ok(public.report(jsonb_build_object('userId', (select b from ids)), 'harassment', 'rude name') > 0, 'report a user');
select throws_ok($$ select public.report('{}', 'spam') $$, '22023', null, 'empty target refused');
select throws_ok($$ select public.report('{"userId":"00000000-0000-4000-8000-000000000000"}', 'nonsense') $$, '23514', null,
                 'unknown reason refused');
select throws_ok($$ select * from public.reports $$, '42501', null, 'reports are private');

-- export ----------------------------------------------------------------------------------------
select is((public.export_my_data()->'profile'->>'username'), 'acc_a', 'export has the profile');
select ok(not (public.export_my_data()->'profile' ? 'mmr'), 'hidden MMR is not exported');
select ok(public.export_my_data() ? 'sessions' and public.export_my_data() ? 'friends', 'export covers sessions and friends');

-- deletion needs a fresh sign-in --------------------------------------------------------------------
select set_config('request.jwt.claims', json_build_object('sub', (select a from ids), 'role', 'authenticated',
                  'iat', extract(epoch from now() - interval '1 hour')::bigint)::text, true);
select throws_ok($$ select public.delete_my_account() $$, '42501', null, 'old session must sign in again');
select set_config('request.jwt.claims', json_build_object('sub', (select a from ids), 'role', 'authenticated',
                  'iat', extract(epoch from now())::bigint)::text, true);
select lives_ok($$ select public.delete_my_account() $$, 'deleted');
select tests.as_owner();
select is((select count(*)::int from public.profiles where id = (select a from ids)), 0, 'profile gone');
select is((select count(*)::int from auth.users where id = (select a from ids)), 0, 'auth user gone');
select is((select count(*)::int from public.account_deletions), 1, 'deletion recorded without the id');
select is((select reporter from public.reports), null, 'reports keep working without the reporter');

-- entitlements ------------------------------------------------------------------------------------
select tests.authenticate_as((select b from ids));
select throws_ok($$ select public.apply_entitlement_event('{}') $$, '42501', null, 'webhook RPC is service-role only');
select tests.as_service();
select is(public.apply_entitlement_event(jsonb_build_object('id', 'evt1', 'type', 'INITIAL_PURCHASE', 'app_user_id', (select b from ids),
          'entitlement_ids', '["pro"]'::jsonb, 'product_id', 'pro_monthly', 'store', 'APP_STORE',
          'event_timestamp_ms', (extract(epoch from now()) * 1000)::bigint,
          'expiration_at_ms', (extract(epoch from now() + interval '30 days') * 1000)::bigint)), 'applied', 'purchase applied');
select is(public.apply_entitlement_event(jsonb_build_object('id', 'evt1', 'type', 'INITIAL_PURCHASE', 'app_user_id', (select b from ids))),
          'duplicate', 'same event id is idempotent');
select tests.as_owner();
select is((select is_pro from public.profiles where id = (select b from ids)), true, 'b is Pro');
select tests.as_service();
select public.apply_entitlement_event(jsonb_build_object('id', 'evt0', 'type', 'EXPIRATION', 'app_user_id', (select b from ids),
          'entitlement_ids', '["pro"]'::jsonb, 'event_timestamp_ms', (extract(epoch from now() - interval '1 day') * 1000)::bigint));
select tests.as_owner();
select is((select is_pro from public.profiles where id = (select b from ids)), true, 'an older out-of-order event does not undo Pro');
select tests.as_service();
select is(public.apply_entitlement_event('{"id":"evt9","type":"INITIAL_PURCHASE","app_user_id":"$RCAnonymousID:abc"}'), 'unknown_user',
          'anonymous ids are logged and ignored');

select * from finish();
rollback;
