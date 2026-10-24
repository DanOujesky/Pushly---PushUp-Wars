-- 0026 — Trophy-first stats (D-067): one call for the Stats screen's main section — trophies, league and the next
-- step, live global rank, season end, win / loss record with streaks, trophy history, recent battles and the players
-- just above me ("next up on the ladder"). Push-up stats stay in get_stats (secondary section).

create or replace function public.get_battle_stats() returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  p public.profiles;
  v_league jsonb;
  v_next jsonb;
  v_wins int := 0;
  v_losses int := 0;
  v_draws int := 0;
  v_best_streak int := 0;
  v_run int := 0;
  r record;
  v_history jsonb;
  v_start int;
begin
  select * into p from public.profiles where id = me;
  v_league := app.league_for(p.trophies);
  -- next tier / league: the smallest trophy count above mine with a different league or tier
  select jsonb_build_object('at', n.t, 'league', app.league_for(n.t)->>'league', 'tier', app.league_for(n.t)->>'tier')
    into v_next
    from (select t from unnest(array[200, 400, 600, 800, 1000, 1200, 1466, 1732, 2000, 2333, 2666, 3000, 3333, 3666, 4000, 5000]) t
           where t > p.trophies order by t limit 1) n;

  -- record over settled battles against people (ghosts / bots are practice), oldest first for streaks
  for r in select case when b.result->>'winner' is null then 'draw'
                       when b.result->>'winner' = case when b.player_a = me then 'a' else 'b' end then 'win'
                       else 'loss' end as outcome
             from public.battles b
            where (b.player_a = me or b.player_b = me) and b.status = 'settled' and b.type <> 'ghost'
            order by b.settled_at nulls first, b.created_at loop
    if r.outcome = 'win' then
      v_wins := v_wins + 1;
      v_run := v_run + 1;
      v_best_streak := greatest(v_best_streak, v_run);
    elsif r.outcome = 'loss' then
      v_losses := v_losses + 1;
      v_run := 0;
    else
      v_draws := v_draws + 1;
      v_run := 0;
    end if;
  end loop;

  -- trophy history: balance before the window, then every change in the last 60 days (max 200 points)
  select coalesce((select l.balance_after from public.trophy_ledger l
                    where l.user_id = me and l.created_at < now() - interval '60 days'
                    order by l.created_at desc, l.id desc limit 1), 0) into v_start;
  select jsonb_build_array(jsonb_build_object('at', app.utc_iso(now() - interval '60 days'), 'trophies', v_start))
         || coalesce(jsonb_agg(jsonb_build_object('at', app.utc_iso(x.created_at), 'trophies', x.balance_after)
                               order by x.created_at, x.id), '[]')
    into v_history
    from (select * from public.trophy_ledger l where l.user_id = me and l.created_at >= now() - interval '60 days'
           order by l.created_at desc, l.id desc limit 200) x;

  return jsonb_build_object(
    'trophies', p.trophies,
    'bestTrophies', p.best_trophies,
    'league', v_league->>'league',
    'tier', v_league->>'tier',
    'next', v_next,
    'rank', case when p.trophies > 0 then (select count(*) + 1 from public.profiles o where o.trophies > p.trophies) end,
    'seasonEndsAt', (select app.utc_iso(s.ends_at) from public.seasons s where s.id = app.current_season()),
    'record', jsonb_build_object('wins', v_wins, 'losses', v_losses, 'draws', v_draws,
                                 'winStreak', p.win_streak, 'bestWinStreak', greatest(v_best_streak, p.win_streak)),
    'history', v_history,
    'recent', coalesce((
      select jsonb_agg(x.j order by x.at desc) from (
        select coalesce(b.settled_at, b.created_at) at, jsonb_build_object(
          'battleId', b.id, 'mode', b.mode,
          'opponent', case when b.player_a = me then coalesce(b.player_b_name, 'Deleted user') else coalesce(b.player_a_name, 'Deleted user') end,
          'result', case when b.result->>'winner' is null then 'draw'
                         when b.result->>'winner' = case when b.player_a = me then 'a' else 'b' end then 'win' else 'loss' end,
          'delta', case when b.player_a = me then (b.result->'trophies'->>'a')::int else (b.result->'trophies'->>'b')::int end,
          'ranked', b.ranked,
          'at', app.utc_iso(coalesce(b.settled_at, b.created_at))) j
          from public.battles b
         where (b.player_a = me or b.player_b = me) and b.status = 'settled' and b.type <> 'ghost'
         order by coalesce(b.settled_at, b.created_at) desc limit 10) x), '[]'),
    'targets', coalesce((
      select jsonb_agg(jsonb_build_object('userId', o.id, 'username', o.username, 'avatarPreset', o.avatar_preset,
                                          'trophies', o.trophies, 'gap', o.trophies - p.trophies) order by o.trophies, o.id)
        from (select * from public.profiles o
               where o.trophies > p.trophies and o.id <> me and o.username is not null and not app.is_blocked(me, o.id)
               order by o.trophies, o.id limit 3) o), '[]'));
end $$;
revoke all on function public.get_battle_stats() from public, anon;
grant execute on function public.get_battle_stats() to authenticated;
