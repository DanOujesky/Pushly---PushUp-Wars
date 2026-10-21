-- push-send queue API (P6-05): leasing, retries, dead tokens, access.
begin;
\ir _helpers.psql
select plan(11);

create temp table ids as select tests.create_user('p@example.com') u;
grant select on ids to authenticated, anon, service_role;
insert into public.devices (id, user_id, platform, push_token)
select 'd0000000-0000-4000-8000-000000000001', u, 'ios', 'apns-token-0123456789' from ids;
insert into public.push_outbox (user_id, type, category, payload) select u, 'kudos', 'social', '{"username":"tom"}' from ids;
insert into public.push_outbox (user_id, type, category, payload, send_after)
select u, 'later', 'social', '{}', now() + interval '1 hour' from ids;

select tests.authenticate_as((select u from ids));
select throws_ok($$ select public.claim_push_batch(10) $$, '42501', null, 'clients cannot claim pushes');

select tests.as_service();
create temp table b as select public.claim_push_batch(10) j;
grant select on b to service_role;
select is((select jsonb_array_length(j) from b), 1, 'only due rows');
select is((select j->0->'devices'->0->>'token' from b), 'apns-token-0123456789', 'with the device tokens');
select is(jsonb_array_length(public.claim_push_batch(10)), 0, 'a claimed row is leased (no double send)');

select public.finish_push(jsonb_build_array(jsonb_build_object('id', (select (j->0->>'id')::bigint from b), 'ok', false,
                                                               'error', 'timeout', 'retry', true)), '[]');
select tests.as_owner();
select is((select sent_at from public.push_outbox where type = 'kudos'), null, 'retryable failure stays queued');
select is((select last_error from public.push_outbox where type = 'kudos'), 'timeout', 'error kept');

select tests.as_service();
select public.finish_push(jsonb_build_array(jsonb_build_object('id', (select (j->0->>'id')::bigint from b), 'ok', true)),
                          '["d0000000-0000-4000-8000-000000000001"]');
select tests.as_owner();
select isnt((select sent_at from public.push_outbox where type = 'kudos'), null, 'sent');
select is((select push_token from public.devices), null, 'dead token removed');
update public.push_outbox set attempts = 5, send_after = now() - interval '1 minute' where type = 'later';
select tests.as_service();
select is(jsonb_array_length(public.claim_push_batch(10)), 0, 'rows that used 5 attempts are not retried');

select tests.as_owner();
select lives_ok($$ select app.housekeeping(now() + interval '40 days') $$, 'housekeeping runs');
select is((select count(*)::int from public.push_outbox where sent_at is not null), 0, 'old sent pushes purged');

select * from finish();
rollback;
