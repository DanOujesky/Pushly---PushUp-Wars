-- D-076: the trophy board lists players with 0 trophies; Clan Wars pair clans from one member up.
begin;
\ir _helpers.psql
select plan(4);

create temp table ids as select tests.create_user('bw_a@example.com') a, tests.create_user('bw_b@example.com') b;
grant select on ids to authenticated, anon, service_role;
update public.profiles p set username = 'bw_' || substr(p.id::text, 1, 6), onboarding_completed = true
 where p.id in (select a from ids union select b from ids);

select tests.as_owner();
select ok(exists (select 1 from app.board_scores('battles', 'season') s where s.user_id = (select a from ids) and s.score = 0),
          '0 trophies is on the board');
select app.refresh_leaderboards();
select tests.authenticate_as((select a from ids));
select ok(jsonb_array_length(public.get_leaderboard('battles', 'global', 'season')->'rows') >= 2, 'world board shows them');

-- two one-person clans get a war on Monday
select tests.authenticate_as((select a from ids));
select public.create_clan(name => 'Solo Alpha');
select tests.authenticate_as((select b from ids));
select public.create_clan(name => 'Solo Beta');
select tests.as_owner();
select ok(app.clan_war_matchmake(app.war_week_start() + 7) >= 1, 'one-person clans are matched');
select ok(exists (select 1 from public.clan_wars w join public.clans c on c.id in (w.clan_a, w.clan_b)
                  where c.name = 'Solo Alpha' and w.week_start = app.war_week_start() + 7), 'Solo Alpha is at war');

select * from finish();
rollback;
