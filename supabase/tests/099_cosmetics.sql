-- Pro cosmetics (D-074): profile frames and Pro clan emblems.
begin;
\ir _helpers.psql
select plan(11);

create temp table ids as select tests.create_user('cos_a@example.com') a, tests.create_user('cos_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'cos_' || substr(p.id::text, 1, 6), onboarding_completed = true
 where p.id in (select a from ids union select b from ids);
update public.profiles set is_pro = true where id = (select a from ids);

-- frames
select tests.authenticate_as((select a from ids));
select is(public.set_profile_frame('gold')->>'frame', 'gold', 'Pro picks a frame');
select throws_ok($$ select public.set_profile_frame('sparkles') $$, '22023', null, 'unknown frame refused');
select tests.authenticate_as((select b from ids));
select throws_ok($$ select public.set_profile_frame('neon') $$, '42501', null, 'free user cannot pick a frame');
select lives_ok($$ select public.set_profile_frame(null) $$, 'anyone can clear the frame');

select tests.as_owner();
select is(app.user_card((select a from ids), (select b from ids))->>'frame', 'gold', 'others see the frame');
update public.profiles set is_pro = false where id = (select a from ids);
select is(app.user_card((select a from ids), (select b from ids))->>'frame', null, 'frame hidden once Pro ends');
update public.profiles set is_pro = true where id = (select a from ids);

-- clan badges
select tests.authenticate_as((select b from ids));
select throws_ok($$ select public.create_clan('Cos Free', 'COSF', '{"shape":"hex","color":"lime","emblem":"dragon"}') $$,
                 '42501', null, 'free user cannot create a clan with a Pro emblem');
select lives_ok($$ select public.create_clan('Cos Free', 'COSF', '{"shape":"hex","color":"lime","emblem":"wolf"}') $$,
                'free emblems are fine');
select throws_ok($$ select public.update_clan('{"badge":{"shape":"star"}}') $$, '22023', null, 'unknown shape refused');
select throws_ok($$ select public.update_clan('{"badge":{"emblem":"crown"}}') $$, '42501', null,
                 'free leader cannot switch to a Pro emblem');

select tests.authenticate_as((select a from ids));
select is(public.create_clan('Cos Pro', 'COSP', '{"shape":"shield","color":"gold","emblem":"crown"}')->'badge'->>'emblem',
          'crown', 'Pro leader gets the Pro emblem');

select * from finish();
rollback;
