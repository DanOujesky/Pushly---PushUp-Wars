-- 0018 — ghost battles (doc 07 §7, roadmap P7-03): you vs. a recorded rep timeline of a real player of similar MMR
-- or your own best run. Never ranked. Free: 3 a day; Pro: unlimited against your own PB (doc 13 §2).

create table public.ghost_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  mode public.battle_mode not null,
  variant jsonb not null default '{}',
  mmr_at double precision not null,
  reps int not null,
  timeline jsonb not null,                        -- [{t, q, round}] ms since the start
  source_battle uuid references public.battles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index ghost_runs_pick_idx on public.ghost_runs(mode, mmr_at);
create index ghost_runs_user_idx on public.ghost_runs(user_id, mode, reps desc);
alter table public.ghost_runs enable row level security;
revoke all on public.ghost_runs from anon, authenticated;     -- read through start_ghost_battle only

-- Contribution opt-out (doc 16 §4): profiles that don't want to appear as ghosts.
alter table public.profiles add column ghost_opt_out boolean not null default false;

-- Every settled human battle side with verified reps becomes a ghost run (public profiles that didn't opt out).
create or replace function app.on_battle_settled_ghosts() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  r record;
  v_reps jsonb;
  v_flag text;
begin
  if new.status <> 'settled' or old.status = 'settled' or new.ghost_run_id is not null then return new; end if;
  for r in select p.id, p.mmr from public.profiles p
            where p.id in (new.player_a, new.player_b) and p.profile_visibility = 'public' and not p.ghost_opt_out loop
    select reps, flag into v_reps, v_flag from app.battle_reps(new, r.id);
    continue when v_flag is not null or jsonb_array_length(v_reps) < 5;
    insert into public.ghost_runs (user_id, mode, variant, mmr_at, reps, timeline, source_battle)
    values (r.id, new.mode, new.variant, r.mmr, jsonb_array_length(v_reps), v_reps, new.id);
  end loop;
  return new;
end $$;
create trigger battles_settled_ghosts after update of status on public.battles
  for each row execute function app.on_battle_settled_ghosts();

-- The ghost side of a battle uses the recorded timeline; humans use their (capped) events as before.
create or replace function app.battle_reps(v public.battles, uid uuid, out reps jsonb, out flag text)
language plpgsql stable security definer set search_path = public, app as $$
declare
  v_cap int;
  v_any boolean;
begin
  if uid is null and v.ghost_run_id is not null then
    select g.timeline into reps from public.ghost_runs g where g.id = v.ghost_run_id;
    reps := coalesce(reps, '[]');
    flag := null;
    return;
  end if;
  select bool_or(true), sum(case when s.verified then s.reps_counted else 0 end), bool_and(s.verified)
    into v_any, v_cap, flag
    from public.rep_sessions s where s.battle_id = v.id and s.user_id = uid;
  if v_any is null then
    v_cap := null;
    flag := 'missing_log';
  elsif flag = 'false' then
    flag := 'unverified_log';
  else
    flag := null;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('t', e.t_end_server_ms, 'q', coalesce(e.quality, 0), 'round', e.round_index)
                            order by e.t_end_server_ms, e.id), '[]')
    into reps
    from (select * from public.battle_events where battle_id = v.id and user_id = uid
           order by t_end_server_ms, id limit coalesce(v_cap, 100000)) e;
end $$;

-- Winner as seen by the viewer from the result letter (works for ghosts, whose side has no user id).
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
      'a', (select count(*) from public.battle_events e where e.battle_id = b.id and e.user_id = b.player_a),
      'b', case when b.ghost_run_id is null
                then (select count(*) from public.battle_events e where e.battle_id = b.id and e.user_id = b.player_b)
                else (select count(*) from public.ghost_runs g, jsonb_array_elements(g.timeline) r
                       where g.id = b.ghost_run_id and b.start_at is not null
                         and (r->>'t')::bigint <= extract(epoch from now() - b.start_at) * 1000) end),
    'result', b.result,
    'winner', case when b.result->>'winner' is null then null
                   when b.result->>'winner' = (case when viewer = b.player_b then 'b' else 'a' end) then 'me'
                   else 'opponent' end,
    'ghost', b.ghost_run_id is not null,
    'livekitRoom', b.livekit_room, 'createdAt', app.utc_iso(b.created_at))
  from public.battles b where b.id = bid
$$;

-- Ghosts settle as soon as the player's log arrives (there is no second log to wait for).
create or replace function app.on_rep_log_battle() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  v_bid uuid;
begin
  if new.log->'context'->>'type' = 'battle' and (new.log->'context'->>'battleId') ~ '^[0-9a-fA-F-]{36}$' then
    v_bid := (new.log->'context'->>'battleId')::uuid;
    update public.rep_sessions s set battle_id = v_bid
     where s.id = new.session_id
       and exists (select 1 from public.battles b where b.id = v_bid and s.user_id in (b.player_a, b.player_b));
    if found then
      perform app.settle_battle(v_bid, (select ghost_run_id is not null from public.battles where id = v_bid));
    end if;
  end if;
  return new;
end $$;

-- start_ghost_battle(mode, own_best): a similar-MMR ghost (not yourself), or your own best run of that mode.
-- Starts right away (countdown 3.5 s). Returns the battle plus the ghost timeline for the on-screen opponent.
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
  select count(*) into v_today from public.battles
   where player_a = me and type = 'ghost' and created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
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

-- Privacy setting: let profile updates switch ghost contribution (doc 16 §4).
create or replace function public.set_ghost_opt_out(opt_out boolean) returns void
language sql security definer set search_path = public, app as $$
  update public.profiles set ghost_opt_out = opt_out where id = app.require_user()
$$;
revoke all on function public.set_ghost_opt_out(boolean) from public, anon;
grant execute on function public.set_ghost_opt_out(boolean) to authenticated;
grant execute on all functions in schema app to service_role;
