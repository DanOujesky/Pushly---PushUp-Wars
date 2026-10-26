-- 0031 — D-075: ranked Arena Bots when nobody is in the queue, clans without a typed tag, no War Chests.
--
-- * Quick match: after 10 s in the queue the player gets a ranked battle against a labelled "Arena Bot". The bot is a
--   synthetic rep timeline whose pace follows the player's trophies along a steep curve (app.arena_bot_reps), so
--   climbing gets very hard: Champion bots do ~52 strict push-ups a minute, the Legend line (5,000) ~75, and they keep
--   getting faster above it. Trophies change for the player only (apply_ranked against equal trophies); MMR is not
--   touched, so human matchmaking stays human. Bots are never shown as people (D-063).
-- * Clans: the tag is no longer typed by the founder — create_clan picks a unique one from the name when none is given.
-- * War Chests are gone (founder): finishing a war no longer grants chests. Old unopened chests stay in the table but
--   the apps don't show them anymore.

-- ---------------------------------------------------------------------------------------------------------- bots
alter table public.ghost_runs drop constraint if exists ghost_runs_bot_level_check;
alter table public.ghost_runs add constraint ghost_runs_bot_level_check
  check (bot_level in ('beginner', 'rookie', 'athlete', 'pro', 'champion', 'arena'));

-- Push-ups per minute (max reps, 60 s) of the Arena Bot at a trophy count. Linear between the points, flat after 6,000.
create or replace function app.arena_bot_reps(trophies int) returns double precision
language plpgsql immutable as $$
declare
  pts int[][] := array[[0, 10], [300, 14], [600, 18], [1200, 25], [2000, 33], [3000, 42], [4000, 52], [4500, 61],
                       [5000, 75], [6000, 88]];
  i int;
  t int := greatest(coalesce(trophies, 0), 0);
begin
  for i in 1..array_length(pts, 1) - 1 loop
    if t <= pts[i + 1][1] then
      return pts[i][2] + (pts[i + 1][2] - pts[i][2]) * (t - pts[i][1])::double precision / (pts[i + 1][1] - pts[i][1]);
    end if;
  end loop;
  return pts[array_length(pts, 1)][2];
end $$;

-- Base ms per rep so the fatigue model of app.bot_timeline (+1.2 % per rep) lands on `reps` in 59.6 s.
create or replace function app.arena_bot_base_ms(trophies int) returns double precision
language sql immutable as $$
  select 59600 / (r + 0.006 * r * (r - 1)) from (select app.arena_bot_reps(trophies) r) x
$$;

-- Same timeline shapes as app.bot_timeline (0024), with an explicit pace.
create or replace function app.bot_timeline_pace(p_mode text, p_variant jsonb, p_base double precision) returns jsonb
language plpgsql volatile set search_path = public, app as $$
declare
  v_out jsonb := '[]';
  v_t double precision;
  v_k int := 0;
  v_end double precision;
  v_target int;
  r int;
begin
  if p_mode in ('max_reps', 'speed') then
    v_end := case when p_mode = 'max_reps' then coalesce((p_variant->>'durationS')::int, 60) * 1000 else 120000 end;
    v_target := case when p_mode = 'speed' then coalesce((p_variant->>'targetReps')::int, 20) else 100000 end;
    v_t := 400;
    loop
      v_t := v_t + p_base * (1 + 0.012 * v_k) * (0.9 + random() * 0.2);
      exit when v_t >= v_end or v_k >= v_target;
      v_out := v_out || jsonb_build_object('t', round(v_t)::bigint, 'q', 72 + floor(random() * 24)::int, 'round', 0);
      v_k := v_k + 1;
    end loop;
  elsif p_mode = 'best_of_3' then
    for r in 0..2 loop
      v_t := r * 135000 + 400;
      loop
        v_t := v_t + p_base * (1 + 0.012 * v_k) * (0.9 + random() * 0.2);
        exit when v_t >= r * 135000 + 90000;
        v_out := v_out || jsonb_build_object('t', round(v_t)::bigint, 'q', 72 + floor(random() * 24)::int, 'round', r);
        v_k := v_k + 1;
      end loop;
      v_k := v_k / 2;
    end loop;
  else
    raise exception 'mode not available against bots' using errcode = '22023';
  end if;
  return v_out;
end $$;

-- A ranked battle against an Arena Bot at the player's trophies (countdown 3.5 s). ghost_runs.mmr_at = bot trophies.
create or replace function app.start_arena_bot(me uuid, p_mode text) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  p public.profiles;
  v_variant jsonb := app.battle_variant(p_mode, '{}', true);
  v_timeline jsonb;
  v_gid uuid;
  v_id uuid;
begin
  if p_mode not in ('max_reps', 'speed', 'best_of_3') then
    raise exception 'mode not available against bots' using errcode = '22023';
  end if;
  select * into p from public.profiles where id = me;
  if (select count(*) from public.battles b join public.ghost_runs g on g.id = b.ghost_run_id
       where b.player_a = me and g.bot_level = 'arena' and b.created_at > now() - interval '1 day') >= 100 then
    raise exception 'bot battle limit reached' using errcode = 'P0001', hint = 'bot_limit';
  end if;
  v_timeline := app.bot_timeline_pace(p_mode, v_variant, app.arena_bot_base_ms(p.trophies));
  insert into public.ghost_runs (user_id, bot_level, mode, variant, mmr_at, reps, timeline)
  values (null, 'arena', p_mode::public.battle_mode, v_variant, p.trophies, jsonb_array_length(v_timeline), v_timeline)
  returning id into v_gid;
  insert into public.battles (type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, ghost_run_id,
                              status, ready_a, ready_b, start_at, season_id)
  values ('ghost', p_mode::public.battle_mode, v_variant, true, me, null, p.username, 'Arena Bot', v_gid,
          'countdown', true, true, now() + interval '3500 milliseconds', app.current_season())
  returning id into v_id;
  return app.battle_json(v_id, me) || jsonb_build_object('ghostTimeline', v_timeline);
end $$;

-- matchmaking_bot(): nobody found after 10 s → leave the queue and fight a ranked Arena Bot in the queued mode.
create or replace function public.matchmaking_bot() returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  q public.matchmaking_queue;
begin
  select * into q from public.matchmaking_queue where user_id = me for update;
  if not found then raise exception 'not in the queue' using errcode = 'P0002', hint = 'not_queued'; end if;
  if q.battle_id is not null then
    delete from public.matchmaking_queue where user_id = me;
    return app.battle_json(q.battle_id, me);
  end if;
  if q.joined_at > now() - interval '9 seconds' then
    raise exception 'still searching' using errcode = 'P0001', hint = 'too_early';
  end if;
  delete from public.matchmaking_queue where user_id = me;
  return app.start_arena_bot(me, q.mode::text);
end $$;
revoke all on function public.matchmaking_bot() from public, anon;
grant execute on function public.matchmaking_bot() to authenticated;

-- settle_battle (0014) + ranked Arena Bot battles: only the player's trophies change, against the bot's trophies.
create or replace function app.settle_battle(bid uuid, force boolean, forfeit_by text default null) returns boolean
language plpgsql security definer set search_path = public, app as $$
declare
  v public.battles;
  ra jsonb;
  rb jsonb;
  fa text;
  fb text;
  d jsonb;
  pa public.profiles;
  pb public.profiles;
  na jsonb;
  nb jsonb;
  ga jsonb;
  gb jsonb;
  v_counted boolean;
  v_winner uuid;
  v_outcome_a text;
  v_logs int;
  v_bot_trophies int;
begin
  select * into v from public.battles where id = bid for update;
  if not found or v.status not in ('countdown', 'live', 'finished') or v.start_at is null then return false; end if;
  select count(distinct user_id) into v_logs from public.rep_sessions where battle_id = v.id;
  if not force and forfeit_by is null and v_logs < 2
     and now() < v.start_at + make_interval(secs => app.battle_max_ms(v.mode::text, v.variant) / 1000.0 + 30) then
    return false;                       -- wait for both logs or the timeout
  end if;
  select reps, flag into ra, fa from app.battle_reps(v, v.player_a);
  select reps, flag into rb, fb from app.battle_reps(v, v.player_b);
  if forfeit_by is not null then
    d := jsonb_build_object('winner', case when forfeit_by = 'a' then 'b' else 'a' end, 'reason', 'forfeit',
                            'a', app.b_side(ra), 'b', app.b_side(rb));
  else
    d := app.decide_battle(v.mode::text, v.variant, ra, rb);
  end if;
  v_winner := case d->>'winner' when 'a' then v.player_a when 'b' then v.player_b end;
  v_outcome_a := case d->>'winner' when 'a' then 'win' when 'b' then 'loss' else 'draw' end;

  select g.mmr_at::int into v_bot_trophies from public.ghost_runs g where g.id = v.ghost_run_id and g.bot_level = 'arena';

  -- Ranked friend battles: max 3 counted per pair per UTC day (doc 06 §7).
  v_counted := v.ranked and v.player_a is not null and (v.player_b is not null or v_bot_trophies is not null);
  if v_counted and v.type = 'friend_ranked' then
    v_counted := (select count(*) from public.battles x
                   where x.type = 'friend_ranked' and x.status = 'settled' and x.result->>'counted' = 'true'
                     and least(x.player_a, x.player_b) = least(v.player_a, v.player_b)
                     and greatest(x.player_a, x.player_b) = greatest(v.player_a, v.player_b)
                     and x.settled_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') < 3;
  end if;

  if v_counted and v.player_b is null then
    -- Arena Bot: the player's trophies only (no MMR change, so human matchmaking stays human)
    select * into pa from public.profiles where id = v.player_a for update;
    na := app.apply_ranked(jsonb_build_object('trophies', pa.trophies, 'floor', pa.trophy_floor,
            'placement_left', pa.placement_battles_left, 'win_streak', pa.win_streak), v_bot_trophies, v_outcome_a);
    update public.profiles set trophies = (na->>'trophies')::int, trophy_floor = (na->>'floor')::int,
           placement_battles_left = (na->>'placement_left')::int, win_streak = (na->>'win_streak')::int,
           best_trophies = greatest(best_trophies, (na->>'trophies')::int)
     where id = pa.id;
    insert into public.trophy_ledger (user_id, battle_id, delta, balance_after, reason, season_id) values
      (pa.id, v.id, (na->>'delta')::int, (na->>'trophies')::int, 'battle_' || v_outcome_a, v.season_id);
  elsif v_counted then
    select * into pa from public.profiles where id = v.player_a for update;
    select * into pb from public.profiles where id = v.player_b for update;
    na := app.apply_ranked(jsonb_build_object('trophies', pa.trophies, 'floor', pa.trophy_floor,
            'placement_left', pa.placement_battles_left, 'win_streak', pa.win_streak), pb.trophies, v_outcome_a);
    nb := app.apply_ranked(jsonb_build_object('trophies', pb.trophies, 'floor', pb.trophy_floor,
            'placement_left', pb.placement_battles_left, 'win_streak', pb.win_streak), pa.trophies,
            case v_outcome_a when 'win' then 'loss' when 'loss' then 'win' else 'draw' end);
    ga := app.glicko2(pa.mmr, pa.mmr_rd, pa.mmr_vol, jsonb_build_array(jsonb_build_object('rating', pb.mmr, 'rd', pb.mmr_rd,
            'score', case v_outcome_a when 'win' then 1 when 'loss' then 0 else 0.5 end)));
    gb := app.glicko2(pb.mmr, pb.mmr_rd, pb.mmr_vol, jsonb_build_array(jsonb_build_object('rating', pa.mmr, 'rd', pa.mmr_rd,
            'score', case v_outcome_a when 'win' then 0 when 'loss' then 1 else 0.5 end)));
    update public.profiles set trophies = (na->>'trophies')::int, trophy_floor = (na->>'floor')::int,
           placement_battles_left = (na->>'placement_left')::int, win_streak = (na->>'win_streak')::int,
           best_trophies = greatest(best_trophies, (na->>'trophies')::int),
           mmr = (ga->>'rating')::double precision, mmr_rd = (ga->>'rd')::double precision, mmr_vol = (ga->>'vol')::double precision
     where id = pa.id;
    update public.profiles set trophies = (nb->>'trophies')::int, trophy_floor = (nb->>'floor')::int,
           placement_battles_left = (nb->>'placement_left')::int, win_streak = (nb->>'win_streak')::int,
           best_trophies = greatest(best_trophies, (nb->>'trophies')::int),
           mmr = (gb->>'rating')::double precision, mmr_rd = (gb->>'rd')::double precision, mmr_vol = (gb->>'vol')::double precision
     where id = pb.id;
    insert into public.trophy_ledger (user_id, battle_id, delta, balance_after, reason, season_id) values
      (pa.id, v.id, (na->>'delta')::int, (na->>'trophies')::int, 'battle_' || v_outcome_a, v.season_id),
      (pb.id, v.id, (nb->>'delta')::int, (nb->>'trophies')::int,
       'battle_' || case v_outcome_a when 'win' then 'loss' when 'loss' then 'win' else 'draw' end, v.season_id);
  end if;

  update public.battles set status = 'settled', settled_at = now(), ended_at = coalesce(ended_at, now()), winner = v_winner,
         result = d || jsonb_build_object('counted', v_counted,
           'trophies', jsonb_build_object('a', coalesce((na->>'delta')::int, 0), 'b', coalesce((nb->>'delta')::int, 0)),
           'flags', jsonb_build_object('a', fa, 'b', fb))
   where id = v.id;
  return true;
end $$;

-- ---------------------------------------------------------------------------------------------------------- clans
-- A unique tag from the name: its letters and digits, 3–5 long, with a number when taken ("Iron Mornings" → IRONM).
create or replace function app.clan_tag_from(p_name text) returns text
language plpgsql volatile set search_path = public, app as $$
declare
  v_base text := upper(regexp_replace(coalesce(p_name, ''), '[^A-Za-z0-9]', '', 'g'));
  v_tag text;
  i int := 0;
begin
  if length(v_base) < 3 then v_base := rpad(v_base, 3, 'X'); end if;
  v_tag := left(v_base, 5);
  while exists (select 1 from public.clans c where c.tag = v_tag) loop
    i := i + 1;
    v_tag := left(v_base, 5 - length(i::text)) || i::text;
    if i > 9999 then
      v_tag := upper(substr(md5(random()::text), 1, 5));
    end if;
  end loop;
  return v_tag;
end $$;

-- create_clan (0015): the tag is optional now; without one the server picks it from the name.
create or replace function public.create_clan(name text, tag text default null, badge jsonb default '{}', description text default '',
                                              join_policy text default 'open', min_trophies int default 0,
                                              country text default null) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_id uuid;
  v_tag text := nullif(upper(trim(coalesce(create_clan.tag, ''))), '');
begin
  if exists (select 1 from public.clan_members where user_id = me) then
    raise exception 'leave your clan first' using errcode = '22023', hint = 'already_in_clan';
  end if;
  if not exists (select 1 from public.profiles where id = me and onboarding_completed) then
    raise exception 'finish your profile first' using errcode = '22023';
  end if;
  if char_length(trim(name)) not between 3 and 24 or app.has_profanity(name) then
    raise exception 'invalid clan name' using errcode = '22023', hint = 'invalid_name';
  end if;
  if v_tag is not null and (v_tag !~ '^[A-Z0-9]{3,5}$' or app.has_profanity(v_tag)) then
    raise exception 'invalid clan tag' using errcode = '22023', hint = 'invalid_tag';
  end if;
  if app.has_profanity(description) then raise exception 'invalid description' using errcode = '22023'; end if;
  if exists (select 1 from public.clans c where c.name = trim(create_clan.name)::citext) then
    raise exception 'name taken' using errcode = '23505', hint = 'taken';
  end if;
  perform app.hit_rate_limit(me, 'create_clan', 3, interval '1 day');
  v_tag := coalesce(v_tag, app.clan_tag_from(name));
  begin
    insert into public.clans (name, tag, badge, description, join_policy, min_trophies, country, created_by)
    values (trim(name), v_tag, coalesce(badge, '{}'), coalesce(description, ''), join_policy::public.join_policy,
            greatest(coalesce(min_trophies, 0), 0), nullif(upper(country), ''), me)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'name or tag taken' using errcode = '23505', hint = 'taken';
  end;
  perform app.clan_add_member(v_id, me, 'leader');
  return app.clan_json(v_id, me);
end $$;

-- ---------------------------------------------------------------------------------------------------------- chests
drop trigger if exists clan_wars_chests on public.clan_wars;

grant execute on all functions in schema app to service_role;
