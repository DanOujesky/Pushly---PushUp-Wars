-- 0024 — practice bots (D-063): clearly labelled computer opponents ("Bot · Athlete") built on the ghost machinery.
-- A bot is a synthetic rep timeline at a fixed level, never a fake person: no profile, no leaderboard entry, never
-- ranked, never trophies (ghost rules). Used for "Practice vs bot", as the quick-match fallback when nobody is
-- online, and as the ghost fallback when no human ghost run of a similar level exists yet.

alter table public.ghost_runs alter column user_id drop not null;
alter table public.ghost_runs add column bot_level text
  check (bot_level in ('beginner', 'rookie', 'athlete', 'pro', 'champion'));
alter table public.ghost_runs add constraint ghost_runs_owner_chk check ((user_id is null) <> (bot_level is null));

-- Level that fits a player (MMR starts at 1500 → rookie).
create or replace function app.bot_level_for(mmr double precision) returns text
language sql immutable as $$
  select case when mmr < 1400 then 'beginner' when mmr < 1550 then 'rookie' when mmr < 1700 then 'athlete'
              when mmr < 1900 then 'pro' else 'champion' end
$$;

-- Display name of a bot level.
create or replace function app.bot_name(level text) returns text
language sql immutable as $$ select 'Bot · ' || initcap(level) $$;

-- A believable rep timeline: base pace per level, slight fatigue per rep, ±12 % jitter. [{t, q, round}] ms since GO.
-- Best of 3 follows the fixed clock (round r = [r·135 s, r·135 s + 90 s)), fatigue carries over between rounds.
create or replace function app.bot_timeline(p_mode text, p_variant jsonb, p_level text) returns jsonb
language plpgsql volatile set search_path = public, app as $$
declare
  v_base double precision := case p_level when 'beginner' then 3600 when 'rookie' then 2600 when 'athlete' then 1900
                                          when 'pro' then 1450 when 'champion' then 1100 end;
  v_out jsonb := '[]';
  v_t double precision;
  v_k int := 0;
  v_end double precision;
  v_target int;
  r int;
begin
  if v_base is null then raise exception 'unknown bot level' using errcode = '22023'; end if;
  if p_mode in ('max_reps', 'speed') then
    v_end := case when p_mode = 'max_reps' then coalesce((p_variant->>'durationS')::int, 60) * 1000 else 120000 end;
    v_target := case when p_mode = 'speed' then coalesce((p_variant->>'targetReps')::int, 20) else 100000 end;
    v_t := 400;
    loop
      v_t := v_t + v_base * (1 + 0.012 * v_k) * (0.88 + random() * 0.24);
      exit when v_t >= v_end or v_k >= v_target;
      v_out := v_out || jsonb_build_object('t', round(v_t)::bigint, 'q', 70 + floor(random() * 26)::int, 'round', 0);
      v_k := v_k + 1;
    end loop;
  elsif p_mode = 'best_of_3' then
    for r in 0..2 loop
      v_t := r * 135000 + 400;
      loop
        v_t := v_t + v_base * (1 + 0.012 * v_k) * (0.88 + random() * 0.24);
        exit when v_t >= r * 135000 + 90000;
        v_out := v_out || jsonb_build_object('t', round(v_t)::bigint, 'q', 70 + floor(random() * 26)::int, 'round', r);
        v_k := v_k + 1;
      end loop;
      v_k := v_k / 2;                                   -- the rest recovers half of the fatigue
    end loop;
  else
    raise exception 'mode not available against bots' using errcode = '22023';
  end if;
  return v_out;
end $$;

-- Creates a bot run and an unranked ghost battle against it (countdown 3.5 s). Caller must be the player.
create or replace function app.start_bot(me uuid, p_mode text, p_level text) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  p public.profiles;
  v_variant jsonb := app.battle_variant(p_mode, '{}', true);
  v_level text;
  v_timeline jsonb;
  v_gid uuid;
  v_id uuid;
begin
  if p_mode not in ('max_reps', 'speed', 'best_of_3') then
    raise exception 'mode not available against bots' using errcode = '22023';
  end if;
  select * into p from public.profiles where id = me;
  v_level := coalesce(p_level, app.bot_level_for(p.mmr));
  if (select count(*) from public.battles b join public.ghost_runs g on g.id = b.ghost_run_id
       where b.player_a = me and g.bot_level is not null and b.created_at > now() - interval '1 day') >= 100 then
    raise exception 'bot battle limit reached' using errcode = 'P0001', hint = 'bot_limit';
  end if;
  v_timeline := app.bot_timeline(p_mode, v_variant, v_level);
  insert into public.ghost_runs (user_id, bot_level, mode, variant, mmr_at, reps, timeline)
  values (null, v_level, p_mode::public.battle_mode, v_variant, 0, jsonb_array_length(v_timeline), v_timeline)
  returning id into v_gid;
  insert into public.battles (type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, ghost_run_id,
                              status, ready_a, ready_b, start_at, season_id)
  values ('ghost', p_mode::public.battle_mode, v_variant, false, me, null, p.username, app.bot_name(v_level), v_gid,
          'countdown', true, true, now() + interval '3500 milliseconds', app.current_season())
  returning id into v_id;
  return app.battle_json(v_id, me) || jsonb_build_object('ghostTimeline', v_timeline);
end $$;

-- start_bot_battle(mode, level): practice against a labelled bot. level null = the level that fits you.
create or replace function public.start_bot_battle(mode text, level text default null) returns jsonb
language plpgsql security definer set search_path = public, app as $$
begin
  return app.start_bot(app.require_user(), start_bot_battle.mode, start_bot_battle.level);
end $$;
revoke all on function public.start_bot_battle(text, text) from public, anon;
grant execute on function public.start_bot_battle(text, text) to authenticated;

-- Ghost battles: bots don't count toward the 3-a-day ghost limit, and when no human ghost of the mode exists yet the
-- player races a bot of their level instead of getting an error.
create or replace function public.start_ghost_battle(mode text, own_best boolean default false) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  p public.profiles;
  g public.ghost_runs;
  v_variant jsonb := app.battle_variant(mode, '{}', true);
  v_today int;
  v_id uuid;
  v_name text;
begin
  select * into p from public.profiles where id = me;
  select count(*) into v_today from public.battles b
   where b.player_a = me and b.type = 'ghost'
     and b.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'
     and not exists (select 1 from public.ghost_runs x where x.id = b.ghost_run_id and x.bot_level is not null);
  if v_today >= 3 and not (p.is_pro and own_best) then
    raise exception 'ghost battle limit reached' using errcode = 'P0001', hint = 'ghost_limit';
  end if;
  if own_best then
    select * into g from public.ghost_runs x where x.user_id = me and x.mode = start_ghost_battle.mode::public.battle_mode
                                               and x.variant = v_variant
     order by x.reps desc, x.created_at limit 1;
  else
    select * into g from public.ghost_runs x where x.user_id <> me and x.mode = start_ghost_battle.mode::public.battle_mode
                                               and x.variant = v_variant and not app.is_blocked(me, x.user_id)
     order by abs(x.mmr_at - p.mmr), random() limit 1;
    if not found and start_ghost_battle.mode in ('max_reps', 'speed', 'best_of_3') then
      return app.start_bot(me, start_ghost_battle.mode, null);
    end if;
  end if;
  if not found then raise exception 'no ghost available yet' using errcode = 'P0002', hint = 'no_ghost'; end if;
  v_name := case when own_best then 'Your best' when app.are_friends(me, g.user_id)
                 then (select username from public.profiles where id = g.user_id) else 'Ghost' end;
  insert into public.battles (type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, ghost_run_id,
                              status, ready_a, ready_b, start_at, season_id)
  values ('ghost', start_ghost_battle.mode::public.battle_mode, v_variant, false, me, null, p.username, v_name, g.id,
          'countdown', true, true, now() + interval '3500 milliseconds', app.current_season())
  returning id into v_id;
  return app.battle_json(v_id, me) || jsonb_build_object('ghostTimeline', g.timeline);
end $$;
revoke all on function public.start_ghost_battle(text, boolean) from public, anon;
grant execute on function public.start_ghost_battle(text, boolean) to authenticated;

-- battle_json gains `bot` (level of a bot opponent, else null).
create or replace function app.battle_json(bid uuid, viewer uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('id', b.id, 'type', b.type, 'mode', b.mode, 'variant', b.variant, 'ranked', b.ranked,
    'status', b.status, 'startAt', app.utc_iso(b.start_at), 'endedAt', app.utc_iso(b.ended_at),
    'me', case when viewer = b.player_b then 'b' else 'a' end,
    'opponent', case when viewer = b.player_a then
                  coalesce(app.user_card(b.player_b, viewer), jsonb_build_object('username', b.player_b_name))
                else coalesce(app.user_card(b.player_a, viewer), jsonb_build_object('username', b.player_a_name)) end,
    'ready', jsonb_build_object('a', b.ready_a, 'b', b.ready_b),
    'score', jsonb_build_object(
      'a', (select count(*) from app.battle_live_reps(b, b.player_a)),
      'b', (select count(*) from app.battle_live_reps(b, case when b.ghost_run_id is null then b.player_b end))),
    'lastRepT', jsonb_build_object(
      'a', (select max(x.t) from app.battle_live_reps(b, b.player_a) x),
      'b', (select max(x.t) from app.battle_live_reps(b, case when b.ghost_run_id is null then b.player_b end) x)),
    'rounds', case when b.mode = 'best_of_3' then (
      select jsonb_agg(jsonb_build_object(
               'a', (select count(*) from app.battle_live_reps(b, b.player_a) x where x.round = r),
               'b', (select count(*) from app.battle_live_reps(b, case when b.ghost_run_id is null then b.player_b end) x
                      where x.round = r)) order by r)
        from generate_series(0, 2) r) end,
    'result', b.result,
    'winner', case when b.result->>'winner' is null then null
                   when b.result->>'winner' = (case when viewer = b.player_b then 'b' else 'a' end) then 'me'
                   else 'opponent' end,
    'ghost', b.ghost_run_id is not null,
    'bot', (select g.bot_level from public.ghost_runs g where g.id = b.ghost_run_id),
    'livekitRoom', b.livekit_room, 'createdAt', app.utc_iso(b.created_at))
  from public.battles b where b.id = bid
$$;

grant execute on all functions in schema app to service_role;
