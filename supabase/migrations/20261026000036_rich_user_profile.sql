-- 0036 — Player profile with real stats (D-080): tapping any player (friend, leaderboard, clan member, war fighter)
-- opens a full profile. get_user_profile keeps its shape and adds:
--   clan       — the player's clan (id, name, tag, badge, rating, memberCount, role) or null; clans are public
--   stats.+    — battles {wins, losses, draws, winStreak, bestWinStreak, form (last 10, newest first: W/L/D)},
--                rank (global by trophies, null at 0), level + xp, wake streak now, reps this week and the last 7 days
--                (the player's local days, oldest first), achievements total
-- Visibility rules are unchanged: the extra stats are only there when `visible` (public / friends / self).

create or replace function public.get_user_profile(user_id uuid default null, username text default null) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  p public.profiles;
  v_rel text;
  f public.friendships;
  v_visible boolean;
  v_today date;
  v_wins int := 0;
  v_losses int := 0;
  v_draws int := 0;
  v_best_run int := 0;
  v_run int := 0;
  v_form text[] := '{}';
  r record;
  v_clan jsonb;
begin
  if user_id is not null then
    select * into p from public.profiles x where x.id = get_user_profile.user_id;
  elsif username is not null then
    select * into p from public.profiles x where x.username = get_user_profile.username::citext;
  end if;
  if p.id is null or not p.onboarding_completed or (p.id <> me and app.is_blocked(me, p.id)) then
    return null;
  end if;
  if p.id = me then
    v_rel := 'self';
  else
    select * into f from public.friendships x where x.user_a = least(me, p.id) and x.user_b = greatest(me, p.id);
    v_rel := case when f.status is null then 'none'
                  when f.status::text = 'accepted' then 'friends'
                  when f.status::text = 'pending' and f.requested_by = me then 'outgoing'
                  when f.status::text = 'pending' then 'incoming'
                  else 'none' end;
  end if;
  v_visible := p.id = me or p.profile_visibility = 'public' or (p.profile_visibility = 'friends' and v_rel = 'friends');

  select app.clan_json(m.clan_id, me) || jsonb_build_object('role', m.role) into v_clan
    from public.clan_members m where m.user_id = p.id;

  if v_visible then
    -- battle record against people (bots / ghosts are practice), oldest first for the best streak
    for r in select case when b.result->>'winner' is null then 'D'
                         when b.result->>'winner' = case when b.player_a = p.id then 'a' else 'b' end then 'W'
                         else 'L' end as o
               from public.battles b
              where (b.player_a = p.id or b.player_b = p.id) and b.status = 'settled' and b.type <> 'ghost'
              order by b.settled_at nulls first, b.created_at loop
      if r.o = 'W' then v_wins := v_wins + 1; v_run := v_run + 1; v_best_run := greatest(v_best_run, v_run);
      elsif r.o = 'L' then v_losses := v_losses + 1; v_run := 0;
      else v_draws := v_draws + 1; v_run := 0;
      end if;
      v_form := r.o || v_form;            -- newest first
    end loop;
    v_today := (now() at time zone coalesce(nullif(p.timezone, ''), 'UTC'))::date;
  end if;

  return jsonb_build_object(
    'user', app.user_card(p.id, me),
    'relation', v_rel,
    'visible', v_visible,
    'league', app.league_for(greatest(p.trophies, 0)),
    'clan', v_clan,
    'stats', case when v_visible then jsonb_build_object(
        'repsTotal', coalesce((select a.reps_total from public.user_stats_alltime a where a.user_id = p.id), 0),
        'bestSet', coalesce((select a.best_set from public.user_stats_alltime a where a.user_id = p.id), 0),
        'bestStreak', coalesce((select s.best from public.streaks s where s.user_id = p.id), 0),
        'achievements', (select count(*) from public.user_achievements u where u.user_id = p.id),
        'achievementsTotal', (select count(*) from public.achievement_definitions where active),
        'bestTrophies', p.best_trophies,
        'memberSince', to_char(p.created_at at time zone 'UTC', 'YYYY-MM'),
        'level', p.level,
        'xp', p.xp,
        'rank', case when p.trophies > 0 then (select count(*) + 1 from public.profiles o where o.trophies > p.trophies) end,
        'wakeStreak', coalesce((select s.current from public.streaks s where s.user_id = p.id), 0),
        'repsWeek', coalesce((select sum(d.reps_total) from public.user_stats_daily d
                               where d.user_id = p.id and d.day > v_today - 7 and d.day <= v_today), 0),
        'last7', (select jsonb_agg(coalesce((select d.reps_total from public.user_stats_daily d
                                              where d.user_id = p.id and d.day = x.day), 0) order by x.day)
                    from (select (v_today - i) as day from generate_series(0, 6) i) x),
        'battles', jsonb_build_object('wins', v_wins, 'losses', v_losses, 'draws', v_draws,
                                      'winStreak', p.win_streak, 'bestWinStreak', greatest(v_best_run, p.win_streak),
                                      'form', to_jsonb(v_form[1:10]))) end,
    'headToHead', case when p.id = me then null else (
        select jsonb_build_object(
          'wins', count(*) filter (where b.result->>'winner' = case when b.player_a = me then 'a' else 'b' end),
          'losses', count(*) filter (where b.result->>'winner' = case when b.player_a = me then 'b' else 'a' end),
          'draws', count(*) filter (where b.result->>'winner' is null))
        from public.battles b
       where b.status = 'settled' and ((b.player_a = me and b.player_b = p.id) or (b.player_a = p.id and b.player_b = me))) end);
end $$;
revoke all on function public.get_user_profile(uuid, text) from public, anon;
grant execute on function public.get_user_profile(uuid, text) to authenticated;
