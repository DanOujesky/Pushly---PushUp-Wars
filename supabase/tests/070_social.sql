-- Friends, blocks, search, activity feed, kudos, push enqueue rules (P6-01, doc 15).
begin;
\ir _helpers.psql
select plan(35);

create temp table ids as select tests.create_user('ana@example.com') ana, tests.create_user('tom@example.com') tom,
                                tests.create_user('eve@example.com') eve, tests.create_user('new@example.com') newbie;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = x.name, onboarding_completed = x.done, timezone = 'UTC'
  from (select ana id, 'qana_fit' name, true done from ids union all select tom, 'qtom_lifts', true from ids
        union all select eve, 'qeve.pushes', true from ids union all select newbie, 'qanabel', false from ids) x
 where p.id = x.id;
-- quiet hours off for the push assertions
insert into public.notification_prefs (user_id, prefs) select id, '{"quietStart":"00:00","quietEnd":"00:00"}' from public.profiles;

-- clients cannot write social tables ------------------------------------------------------------
select tests.authenticate_as((select ana from ids));
select throws_ok($$ insert into public.friendships (user_a, user_b, status, requested_by)
                    select least(ana, tom), greatest(ana, tom), 'accepted', ana from ids $$, '42501', null,
                 'no direct friendship inserts');
select throws_ok($$ select * from public.push_outbox $$, '42501', null, 'push_outbox is private');
select throws_ok($$ select * from public.activity_events $$, '42501', null, 'activity_events only via the feed RPC');

-- search ---------------------------------------------------------------------------------------
select is(jsonb_array_length(public.search_users('qan')), 0, 'unfinished profiles and myself are not found');
select is((public.search_users('QTOM')->0->>'username'), 'qtom_lifts', 'case-insensitive prefix search');
select is((public.search_users('qtom')->0->>'relation'), 'none', 'relation none');
select is(jsonb_array_length(public.search_users('%')), 0, 'LIKE wildcards are escaped');

-- request → accept -----------------------------------------------------------------------------
select is(public.send_friend_request((select tom from ids)), 'pending', 'ana asks tom');
select is(public.send_friend_request((select tom from ids)), 'pending', 'asking again is idempotent');
select is((public.search_users('qtom')->0->>'relation'), 'outgoing', 'ana sees outgoing');
select throws_ok($$ select public.send_friend_request((select newbie from ids)) $$, 'P0002', null,
                 'unfinished profiles cannot be asked');
select throws_ok($$ select public.send_friend_request(auth.uid()) $$, 'P0002', null, 'not yourself');

select tests.authenticate_as((select tom from ids));
select is(jsonb_array_length(public.list_friends()->'incoming'), 1, 'tom sees the request');
select is(public.respond_friend_request((select ana from ids), true), 'friends', 'tom accepts');
select is((public.list_friends()->'friends'->0->>'username'), 'qana_fit', 'friends list');
select tests.as_owner();
select ok(app.are_friends((select ana from ids), (select tom from ids)), 'are_friends');

select tests.as_owner();
select is((select count(*)::int from public.push_outbox where type = 'friend_request' and user_id = (select tom from ids)), 1,
          'one request push (collapsed)');
select is((select count(*)::int from public.push_outbox where type = 'friend_accepted' and user_id = (select ana from ids)), 1,
          'accepted push to ana');

-- mutual request = accept ----------------------------------------------------------------------
select tests.authenticate_as((select eve from ids));
select is(public.send_friend_request((select tom from ids)), 'pending', 'eve asks tom');
select tests.authenticate_as((select tom from ids));
select is(public.send_friend_request((select eve from ids)), 'friends', 'tom asking back accepts');

-- feed + kudos ---------------------------------------------------------------------------------
select tests.as_owner();
insert into public.wake_attempts (user_id, local_date, status, score, points, mode)
select tom, current_date, 'succeeded', 25, 17, '{"type":"ringUntilDone"}' from ids;
select tests.authenticate_as((select ana from ids));
select is((public.get_friend_feed()->0->>'kind'), 'wake_beaten', 'ana sees tom''s wake in the feed');
select is((public.get_friend_feed()->0->'payload'->>'reps')::int, 25, 'with the reps');
select is(public.give_kudos((public.get_friend_feed()->0->>'id')::bigint), 1, 'kudos');
select is(public.give_kudos((public.get_friend_feed()->0->>'id')::bigint), 1, 'only once per event');
select is((public.get_friend_feed()->0->>'kudosByMe')::boolean, true, 'kudosByMe');
select throws_ok($$ select public.give_kudos(-1) $$, 'P0002', null, 'unknown event');
select tests.as_owner();
create temp table ev as select max(id) id from public.activity_events;
grant select on ev to authenticated;
select tests.authenticate_as((select newbie from ids));
select throws_ok($$ select public.give_kudos((select id from ev)) $$, 'P0002', null, 'non-friends cannot give kudos');

-- block ----------------------------------------------------------------------------------------
select tests.authenticate_as((select tom from ids));
select is(public.block_user((select ana from ids)), 'blocked', 'tom blocks ana');
select is(jsonb_array_length(public.list_friends()->'blocked'), 1, 'tom sees his block');
select tests.authenticate_as((select ana from ids));
select is((select count(*)::int from public.friendships), 0, 'ana cannot see the block row');
select is(jsonb_array_length(public.search_users('qtom')), 0, 'tom is hidden from ana''s search');
select throws_ok($$ select public.send_friend_request((select tom from ids)) $$, 'P0002', null,
                 'ana cannot ask tom (looks like not found)');
select is(jsonb_array_length(public.get_friend_feed()), 0, 'no feed from tom any more');

-- prefs + caps ---------------------------------------------------------------------------------
select is((public.set_notification_prefs('{"categories":{"social":false}}')->'categories'->>'social')::boolean, false,
          'categories saved');
select throws_ok($$ select public.set_notification_prefs('{"quietStart":"25:00"}') $$, '22023', null, 'bad time rejected');

select * from finish();
rollback;
