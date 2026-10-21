-- Live HUD data for Best of 3 and Turns (doc 07 §2, §6):
--  * Best of 3 runs on a fixed clock: round r = [r·135 s, r·135 s + 90 s), then 45 s rest. The server derives the
--    round from the rep time (the client's round label is ignored) and drops reps done during the rest.
--  * get_battle adds `lastRepT` {a, b} (ms since start of each side's latest rep — Turns needs the opponent's) and
--    `rounds` [{a, b}] (reps per Best-of-3 round so far; raw counts, the result still applies the set rules).
create or replace function app.bo3_round(t bigint) returns int
language sql immutable as $$ select least(2, (t / 135000))::int $$;

create or replace function app.bo3_in_window(t bigint) returns boolean
language sql immutable as $$ select t >= 0 and t < 3 * 135000 and t % 135000 < 90000 $$;

create or replace function public.battle_push_rep(battle_id uuid, reps jsonb) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v public.battles := app.my_battle(battle_id, me);
  v_now_ms bigint;
  v_n int;
begin
  if v.status not in ('countdown', 'live') or v.start_at is null then
    raise exception 'battle not live' using errcode = 'P0001', hint = 'not_live';
  end if;
  v_now_ms := (extract(epoch from now() - v.start_at) * 1000)::bigint;
  if v_now_ms < -1000 then raise exception 'battle not started' using errcode = 'P0001', hint = 'not_live'; end if;
  insert into public.battle_events (battle_id, user_id, round_index, rep_index, t_end_server_ms, quality)
  select v.id, me,
         case when v.mode = 'best_of_3' then app.bo3_round((r->>'t')::bigint) else coalesce((r->>'round')::smallint, 0) end,
         (r->>'i')::int, (r->>'t')::bigint,
         greatest(0, least(100, coalesce((r->>'q')::int, 0)))::smallint
    from jsonb_array_elements(coalesce(reps, '[]')) r
   where (r->>'t')::bigint between 0 and v_now_ms + 2000              -- no reps from the future (2 s clock slack)
     and (r->>'t')::bigint <= app.battle_max_ms(v.mode::text, v.variant)
     and (v.mode <> 'best_of_3' or app.bo3_in_window((r->>'t')::bigint))
  on conflict do nothing;
  get diagnostics v_n = row_count;
  update public.battles b set status = 'live' where b.id = v.id and b.status = 'countdown';
  return v_n;
end $$;
revoke all on function public.battle_push_rep(uuid, jsonb) from public, anon;
grant execute on function public.battle_push_rep(uuid, jsonb) to authenticated;

-- One side's live reps for the HUD: real events, or the ghost timeline up to "now".
create or replace function app.battle_live_reps(b public.battles, uid uuid) returns table (t bigint, round int)
language sql stable security definer set search_path = public, app as $$
  select e.t_end_server_ms, e.round_index::int from public.battle_events e
   where e.battle_id = b.id and e.user_id = uid and uid is not null
  union all
  select (r->>'t')::bigint, coalesce((r->>'round')::int, 0)
    from public.ghost_runs g, jsonb_array_elements(g.timeline) r
   where uid is null and g.id = b.ghost_run_id and b.start_at is not null
     and (r->>'t')::bigint <= extract(epoch from now() - b.start_at) * 1000
$$;

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
    'livekitRoom', b.livekit_room, 'createdAt', app.utc_iso(b.created_at))
  from public.battles b where b.id = bid
$$;
