-- 0014 — battles: schema, trophy + MMR math, results, invites, matchmaking, settlement (doc 07, doc 08 §1–2),
-- roadmap P7-01 / P7-02 / P7-05 / P7-07 backend. Rules mirror tools/reference/pushly_ref/{ranking,battle}.py and are
-- tested against shared/test-vectors/{trophies,battles} (supabase/tests/081_battle_vectors.sql, generated).

-- ---------------------------------------------------------------------------
-- Schema (doc 11 §6)
-- ---------------------------------------------------------------------------
create table public.seasons (
  id smallint primary key,               -- yyyymm - 202600 style: 2026-10 → 2610
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'active' check (status in ('active', 'closed'))
);

alter table public.profiles add column win_streak smallint not null default 0;
alter table public.profiles add column best_trophies int not null default 0;

create table public.battles (
  id uuid primary key default gen_random_uuid(),
  type public.battle_type not null,
  mode public.battle_mode not null,
  variant jsonb not null default '{}',
  ranked boolean not null,
  player_a uuid references public.profiles(id) on delete set null,
  player_b uuid references public.profiles(id) on delete set null,
  player_a_name text not null,
  player_b_name text,
  ghost_run_id uuid,
  status public.battle_status not null default 'created',
  ready_a boolean not null default false,
  ready_b boolean not null default false,
  start_at timestamptz,
  ended_at timestamptz,
  settled_at timestamptz,
  result jsonb,
  winner uuid,
  season_id smallint references public.seasons(id),
  livekit_room text,
  created_at timestamptz not null default now(),
  check (player_a <> player_b)
);
create index battles_player_a_idx on public.battles(player_a, created_at desc);
create index battles_player_b_idx on public.battles(player_b, created_at desc);
create index battles_open_idx on public.battles(status, start_at) where status in ('lobby', 'ready_check', 'countdown', 'live', 'finished');

create table public.battle_events (
  id bigint generated always as identity primary key,
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id uuid not null,
  round_index smallint not null default 0,
  rep_index int not null,
  t_end_server_ms bigint not null,       -- ms since battles.start_at
  quality smallint,
  received_at timestamptz not null default now(),
  unique (battle_id, user_id, round_index, rep_index)
);

create table public.battle_invites (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid references public.profiles(id) on delete cascade,
  code text unique,
  mode public.battle_mode not null,
  variant jsonb not null default '{}',
  ranked boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  battle_id uuid references public.battles(id) on delete set null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index battle_invites_to_idx on public.battle_invites(to_user, status);

create table public.matchmaking_queue (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  mode public.battle_mode not null,
  variant jsonb not null default '{}',
  mmr double precision not null,
  trust_bucket smallint not null,
  region text not null,
  last_opponent uuid,
  battle_id uuid references public.battles(id) on delete set null,   -- set when matched
  joined_at timestamptz not null default now()
);

create table public.trophy_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  battle_id uuid references public.battles(id) on delete set null,
  delta int not null,
  balance_after int not null,
  reason text not null check (reason in ('battle_win', 'battle_loss', 'battle_draw', 'reversal', 'season_reset')),
  season_id smallint references public.seasons(id),
  created_at timestamptz not null default now()
);
create index trophy_ledger_user_idx on public.trophy_ledger(user_id, created_at desc);

do $$
declare t text;
begin
  foreach t in array array['seasons', 'battles', 'battle_events', 'battle_invites', 'matchmaking_queue', 'trophy_ledger'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
create policy seasons_read on public.seasons for select to authenticated using (true);
create policy battles_participants on public.battles for select to authenticated using (auth.uid() in (player_a, player_b));
create policy battle_events_participants on public.battle_events for select to authenticated
  using (exists (select 1 from public.battles b where b.id = battle_id and auth.uid() in (b.player_a, b.player_b)));
create policy battle_invites_own on public.battle_invites for select to authenticated using (auth.uid() in (from_user, to_user));
create policy matchmaking_own on public.matchmaking_queue for select to authenticated using (user_id = auth.uid());
create policy trophy_ledger_own on public.trophy_ledger for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Seasons: calendar month UTC (doc 08 §2.5)
-- ---------------------------------------------------------------------------
create or replace function app.season_id_for(at_ts timestamptz) returns smallint
language sql immutable as $$
  select ((extract(year from at_ts at time zone 'UTC')::int - 2000) * 100 + extract(month from at_ts at time zone 'UTC')::int)::smallint
$$;

create or replace function app.current_season(at_ts timestamptz default now()) returns smallint
language plpgsql security definer set search_path = public, app as $$
declare
  v_id smallint := app.season_id_for(at_ts);
  v_start timestamptz := date_trunc('month', at_ts at time zone 'UTC') at time zone 'UTC';
begin
  insert into public.seasons (id, starts_at, ends_at) values (v_id, v_start, v_start + interval '1 month')
  on conflict (id) do nothing;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Trophies (doc 08 §2, ranking.py). SQL integer "/" truncates toward zero like the reference tdiv.
-- ---------------------------------------------------------------------------
create or replace function app.win_gain(me int, opp int) returns int
language sql immutable as $$ select greatest(10, least(50, 30 + (opp - me) / 25)) $$;

create or replace function app.loss_cost(me int, opp int) returns int
language sql immutable as $$ select greatest(5, least(40, 20 - (opp - me) / 25)) $$;

-- state: {trophies, floor, placement_left, win_streak} → new state + "delta" (applied)
create or replace function app.apply_ranked(state jsonb, opp int, outcome text) returns jsonb
language plpgsql immutable as $$
declare
  v_t int := (state->>'trophies')::int;
  v_floor int := (state->>'floor')::int;
  v_left int := (state->>'placement_left')::int;
  v_streak int := (state->>'win_streak')::int;
  v_delta int;
  v_new int;
begin
  if outcome = 'win' then
    v_delta := app.win_gain(v_t, opp);
    if v_left > 0 then v_delta := v_delta * 3 / 2; end if;
    v_streak := v_streak + 1;
    if v_streak >= 3 then v_delta := v_delta + 3; end if;
  elsif outcome = 'loss' then
    v_delta := case when v_left > 0 then -(app.loss_cost(v_t, opp) / 2) else -app.loss_cost(v_t, opp) end;
    v_streak := 0;
  elsif outcome = 'draw' then
    v_delta := 0;
  else
    raise exception 'outcome %', outcome using errcode = '22023';
  end if;
  v_new := greatest(v_floor, v_t + v_delta);
  v_floor := greatest(v_floor, case when v_new >= 2000 then 2000 when v_new >= 1200 then 1200 when v_new >= 600 then 600 else 0 end);
  return jsonb_build_object('trophies', v_new, 'floor', v_floor, 'placement_left', greatest(0, v_left - 1),
                            'win_streak', v_streak, 'delta', v_new - v_t);
end $$;

create or replace function app.season_reset(t int) returns int
language sql immutable as $$ select case when t <= 2000 then t else 2000 + (t - 2000) / 2 end $$;

create or replace function app.league_for(t int) returns jsonb
language plpgsql immutable as $$
declare
  v_name text;
  v_lo int;
  v_hi int;
  v_size int;
begin
  if t < 0 then raise exception 'negative trophies' using errcode = '22023'; end if;
  if t >= 5000 then return jsonb_build_object('league', 'legend', 'tier', null); end if;
  select n, lo, hi into v_name, v_lo, v_hi from (values ('bronze', 0, 599), ('silver', 600, 1199), ('gold', 1200, 1999),
    ('platinum', 2000, 2999), ('diamond', 3000, 3999), ('champion', 4000, 4999)) l(n, lo, hi) where t between lo and hi;
  if v_name = 'champion' then return jsonb_build_object('league', v_name, 'tier', null); end if;
  v_size := (v_hi - v_lo + 1) / 3;
  return jsonb_build_object('league', v_name, 'tier',
    case when t < v_lo + v_size then 'III' when t < v_lo + 2 * v_size then 'II' else 'I' end);
end $$;

-- ---------------------------------------------------------------------------
-- Glicko-2 (battle.py), one game per rating period.
-- ---------------------------------------------------------------------------
create or replace function app.glicko2(rating double precision, rd double precision, vol double precision, opponents jsonb)
returns jsonb language plpgsql immutable as $$
declare
  c_scale constant double precision := 173.7178;
  c_tau constant double precision := 0.5;
  c_eps constant double precision := 1e-6;
  v_mu double precision := (rating - 1500) / c_scale;
  v_phi double precision := rd / c_scale;
  v_inv double precision := 0;
  v_sum double precision := 0;
  v_v double precision;
  v_delta double precision;
  v_a double precision;
  v_big_a double precision;
  v_big_b double precision;
  v_c double precision;
  v_fa double precision;
  v_fb double precision;
  v_fc double precision;
  v_k int;
  v_vol double precision;
  v_phi_star double precision;
  v_new_phi double precision;
  o jsonb;
  v_mj double precision;
  v_pj double precision;
  v_g double precision;
  v_e double precision;
begin
  if jsonb_array_length(coalesce(opponents, '[]')) = 0 then
    return jsonb_build_object('rating', rating, 'rd', least(350, sqrt(v_phi * v_phi + vol * vol) * c_scale), 'vol', vol);
  end if;
  for o in select * from jsonb_array_elements(opponents) loop
    v_mj := ((o->>'rating')::double precision - 1500) / c_scale;
    v_pj := (o->>'rd')::double precision / c_scale;
    v_g := 1 / sqrt(1 + 3 * v_pj * v_pj / (pi() * pi()));
    v_e := 1 / (1 + exp(-v_g * (v_mu - v_mj)));
    v_inv := v_inv + v_g * v_g * v_e * (1 - v_e);
    v_sum := v_sum + v_g * ((o->>'score')::double precision - v_e);
  end loop;
  v_v := 1 / v_inv;
  v_delta := v_v * v_sum;
  v_a := ln(vol * vol);
  v_big_a := v_a;
  if v_delta * v_delta > v_phi * v_phi + v_v then
    v_big_b := ln(v_delta * v_delta - v_phi * v_phi - v_v);
  else
    v_k := 1;
    while app.glicko2_f(v_a - v_k * c_tau, v_delta, v_phi, v_v, v_a, c_tau) < 0 loop v_k := v_k + 1; end loop;
    v_big_b := v_a - v_k * c_tau;
  end if;
  v_fa := app.glicko2_f(v_big_a, v_delta, v_phi, v_v, v_a, c_tau);
  v_fb := app.glicko2_f(v_big_b, v_delta, v_phi, v_v, v_a, c_tau);
  while abs(v_big_b - v_big_a) > c_eps loop
    v_c := v_big_a + (v_big_a - v_big_b) * v_fa / (v_fb - v_fa);
    v_fc := app.glicko2_f(v_c, v_delta, v_phi, v_v, v_a, c_tau);
    if v_fc * v_fb <= 0 then
      v_big_a := v_big_b;
      v_fa := v_fb;
    else
      v_fa := v_fa / 2;
    end if;
    v_big_b := v_c;
    v_fb := v_fc;
  end loop;
  v_vol := exp(v_big_a / 2);
  v_phi_star := sqrt(v_phi * v_phi + v_vol * v_vol);
  v_new_phi := 1 / sqrt(1 / (v_phi_star * v_phi_star) + 1 / v_v);
  return jsonb_build_object('rating', (v_mu + v_new_phi * v_new_phi * v_sum) * c_scale + 1500,
                            'rd', least(350, v_new_phi * c_scale), 'vol', v_vol);
end $$;

create or replace function app.glicko2_f(x double precision, delta double precision, phi double precision,
                                         v double precision, a double precision, tau double precision)
returns double precision language sql immutable as $$
  select exp(x) * (delta * delta - phi * phi - v - exp(x)) / (2 * power(phi * phi + v + exp(x), 2)) - (x - a) / (tau * tau)
$$;

-- ---------------------------------------------------------------------------
-- Battle results (battle.py decide). Reps: jsonb [{t, q, round}] with t = ms since the start.
-- ---------------------------------------------------------------------------
create or replace function app.b_sorted(reps jsonb) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(r order by (r->>'t')::bigint, i), '[]') from jsonb_array_elements(coalesce(reps, '[]')) with ordinality x(r, i)
$$;

create or replace function app.b_side(reps jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('reps', jsonb_array_length(reps),
    'avgQuality', case when jsonb_array_length(reps) = 0 then 0
                       else floor((select sum((r->>'q')::numeric) from jsonb_array_elements(reps) r) / jsonb_array_length(reps) + 0.5)::int end,
    'lastT', case when jsonb_array_length(reps) = 0 then null else (reps->(jsonb_array_length(reps) - 1)->>'t')::bigint end)
$$;

-- First continuous set: stops at the first pause > gap; only reps ending at or before cap.
create or replace function app.b_continuous(reps jsonb, gap bigint, cap bigint) returns jsonb
language plpgsql immutable as $$
declare
  v_out jsonb := '[]';
  v_prev bigint;
  r jsonb;
begin
  for r in select * from jsonb_array_elements(app.b_sorted(reps)) loop
    exit when (r->>'t')::bigint > cap;
    exit when v_prev is not null and (r->>'t')::bigint - v_prev > gap;
    v_out := v_out || jsonb_build_array(r);
    v_prev := (r->>'t')::bigint;
  end loop;
  return v_out;
end $$;

-- keys: 'field:1' (higher wins) / 'field:-1' (lower wins); null loses. Returns 'a', 'b' or null.
create or replace function app.b_compare(a jsonb, b jsonb, keys text[]) returns text
language plpgsql immutable as $$
declare
  k text;
  v_field text;
  v_dir int;
  x numeric;
  y numeric;
begin
  foreach k in array keys loop
    v_field := split_part(k, ':', 1);
    v_dir := split_part(k, ':', 2)::int;
    x := (a->>v_field)::numeric;
    y := (b->>v_field)::numeric;
    if x is not distinct from y then continue; end if;
    if x is null then return 'b'; end if;
    if y is null then return 'a'; end if;
    return case when (x - y) * v_dir > 0 then 'a' else 'b' end;
  end loop;
  return null;
end $$;

create or replace function app.decide_battle(mode text, variant jsonb, a jsonb, b jsonb) returns jsonb
language plpgsql immutable as $$
declare
  v_cap bigint;
  v_target int;
  sa jsonb;
  sb jsonb;
  v_winner text;
  v_reason text;
  v_sorted jsonb;
  v_rounds jsonb := '[]';
  v_wins_a int := 0;
  v_wins_b int := 0;
  v_tot_a jsonb := '[]';
  v_tot_b jsonb := '[]';
  v_set_a jsonb;
  v_set_b jsonb;
  v_rr jsonb;
  v_first bigint;
  v_rnd int;
  v_window bigint;
  v_prev jsonb;
  v_loser text;
  v_cnt_a jsonb := '[]';
  v_cnt_b jsonb := '[]';
  e jsonb;
  v_done boolean := false;
begin
  a := coalesce(a, '[]');
  b := coalesce(b, '[]');
  if mode = 'max_reps' then
    v_cap := coalesce((variant->>'durationS')::int, 60) * 1000;
    sa := app.b_side((select coalesce(jsonb_agg(r), '[]') from jsonb_array_elements(a) r where (r->>'t')::bigint <= v_cap));
    sb := app.b_side((select coalesce(jsonb_agg(r), '[]') from jsonb_array_elements(b) r where (r->>'t')::bigint <= v_cap));
    v_winner := app.b_compare(sa, sb, array['reps:1', 'avgQuality:1', 'lastT:-1']);
    return jsonb_build_object('winner', v_winner, 'reason', case when v_winner is null then 'draw' else 'reps' end, 'a', sa, 'b', sb);
  end if;

  if mode = 'speed' then
    v_target := coalesce((variant->>'targetReps')::int, 20);
    v_sorted := (select coalesce(jsonb_agg(r order by i), '[]') from jsonb_array_elements(app.b_sorted(a)) with ordinality x(r, i)
                  where (r->>'t')::bigint <= 120000);
    sa := app.b_side((select coalesce(jsonb_agg(r order by i), '[]') from jsonb_array_elements(v_sorted) with ordinality x(r, i) where i <= v_target))
          || jsonb_build_object('finishT', case when jsonb_array_length(v_sorted) >= v_target then (v_sorted->(v_target - 1)->>'t')::bigint end);
    v_sorted := (select coalesce(jsonb_agg(r order by i), '[]') from jsonb_array_elements(app.b_sorted(b)) with ordinality x(r, i)
                  where (r->>'t')::bigint <= 120000);
    sb := app.b_side((select coalesce(jsonb_agg(r order by i), '[]') from jsonb_array_elements(v_sorted) with ordinality x(r, i) where i <= v_target))
          || jsonb_build_object('finishT', case when jsonb_array_length(v_sorted) >= v_target then (v_sorted->(v_target - 1)->>'t')::bigint end);
    if sa->>'finishT' is not null or sb->>'finishT' is not null then
      v_winner := app.b_compare(sa, sb, array['finishT:-1']);
      return jsonb_build_object('winner', v_winner, 'reason', case when v_winner is null then 'draw' else 'target' end, 'a', sa, 'b', sb);
    end if;
    v_winner := app.b_compare(sa, sb, array['reps:1', 'lastT:-1']);
    return jsonb_build_object('winner', v_winner, 'reason', case when v_winner is null then 'draw' else 'reps' end, 'a', sa, 'b', sb);
  end if;

  if mode = 'endurance' then
    sa := app.b_side(app.b_continuous(a, 3000, 600000));
    sb := app.b_side(app.b_continuous(b, 3000, 600000));
    v_winner := app.b_compare(sa, sb, array['reps:1', 'lastT:-1']);
    return jsonb_build_object('winner', v_winner, 'reason', case when v_winner is null then 'draw' else 'reps' end, 'a', sa, 'b', sb);
  end if;

  if mode = 'best_of_3' then
    for v_rnd in 0..2 loop
      v_rr := (select coalesce(jsonb_agg(r), '[]') from jsonb_array_elements(a) r where coalesce((r->>'round')::int, 0) = v_rnd);
      v_first := coalesce((select min((r->>'t')::bigint) from jsonb_array_elements(v_rr) r), 0);
      v_set_a := app.b_continuous(v_rr, 2000, v_first + 90000);
      v_rr := (select coalesce(jsonb_agg(r), '[]') from jsonb_array_elements(b) r where coalesce((r->>'round')::int, 0) = v_rnd);
      v_first := coalesce((select min((r->>'t')::bigint) from jsonb_array_elements(v_rr) r), 0);
      v_set_b := app.b_continuous(v_rr, 2000, v_first + 90000);
      v_tot_a := v_tot_a || v_set_a;
      v_tot_b := v_tot_b || v_set_b;
      v_winner := case when jsonb_array_length(v_set_a) > jsonb_array_length(v_set_b) then 'a'
                       when jsonb_array_length(v_set_b) > jsonb_array_length(v_set_a) then 'b' end;
      if v_winner = 'a' then v_wins_a := v_wins_a + 1; elsif v_winner = 'b' then v_wins_b := v_wins_b + 1; end if;
      v_rounds := v_rounds || jsonb_build_array(jsonb_build_object('a', jsonb_array_length(v_set_a), 'b', jsonb_array_length(v_set_b),
                                                                    'winner', v_winner));
      exit when greatest(v_wins_a, v_wins_b) >= 2;
    end loop;
    sa := app.b_side(v_tot_a) || jsonb_build_object('rounds', v_wins_a);
    sb := app.b_side(v_tot_b) || jsonb_build_object('rounds', v_wins_b);
    v_winner := app.b_compare(sa, sb, array['rounds:1']);
    v_reason := 'rounds';
    if v_winner is null then
      v_winner := app.b_compare(sa, sb, array['reps:1', 'avgQuality:1']);
      v_reason := case when v_winner is null then 'draw' else 'reps' end;
    end if;
    return jsonb_build_object('winner', v_winner, 'reason', v_reason, 'a', sa, 'b', sb, 'rounds', v_rounds);
  end if;

  if mode = 'turns' then
    v_window := 5000 + least(coalesce((variant->>'latencyMs')::int, 0), 500);
    for e in select x.r || jsonb_build_object('p', x.p) from (
               select r, 'a' p, i from jsonb_array_elements(a) with ordinality y(r, i)
               union all select r, 'b' p, i from jsonb_array_elements(b) with ordinality y(r, i)) x
             order by (x.r->>'t')::bigint, x.p, x.i loop
      if v_prev is not null and e->>'p' = v_prev->>'p' then continue; end if;
      if v_prev is not null and (e->>'t')::bigint - (v_prev->>'t')::bigint > v_window then
        v_loser := e->>'p';
        v_done := true;
        exit;
      end if;
      e := e - 'p' || jsonb_build_object('p', e->>'p');
      if e->>'p' = 'a' then v_cnt_a := v_cnt_a || jsonb_build_array(e - 'p'); else v_cnt_b := v_cnt_b || jsonb_build_array(e - 'p'); end if;
      v_prev := e;
      if jsonb_array_length(v_cnt_a) + jsonb_array_length(v_cnt_b) >= 200 then
        v_done := true;
        exit;
      end if;
    end loop;
    if not v_done and v_prev is not null then
      v_loser := case when v_prev->>'p' = 'a' then 'b' else 'a' end;
    end if;
    sa := app.b_side(v_cnt_a);
    sb := app.b_side(v_cnt_b);
    if v_loser is not null then
      return jsonb_build_object('winner', case when v_loser = 'a' then 'b' else 'a' end, 'reason', 'turn_missed', 'a', sa, 'b', sb);
    end if;
    v_winner := case when v_prev is null then null else app.b_compare(sa, sb, array['avgQuality:1']) end;
    return jsonb_build_object('winner', v_winner, 'reason', case when v_winner is null then 'draw' else 'quality' end, 'a', sa, 'b', sb);
  end if;

  raise exception 'unknown mode %', mode using errcode = '22023';
end $$;

-- ---------------------------------------------------------------------------
-- Lifecycle helpers
-- ---------------------------------------------------------------------------
-- Allowed variants (doc 07 §2): quick match uses the defaults; other values are friend-only.
create or replace function app.battle_variant(mode text, variant jsonb, quick boolean) returns jsonb
language plpgsql immutable as $$
declare
  v jsonb := coalesce(variant, '{}');
begin
  if mode = 'max_reps' then
    v := jsonb_build_object('durationS', coalesce((v->>'durationS')::int, 60));
    if (v->>'durationS')::int not in (30, 60, 120) or (quick and (v->>'durationS')::int <> 60) then
      raise exception 'invalid duration' using errcode = '22023';
    end if;
  elsif mode = 'speed' then
    v := jsonb_build_object('targetReps', coalesce((v->>'targetReps')::int, 20));
    if (v->>'targetReps')::int not in (10, 20, 30) or (quick and (v->>'targetReps')::int <> 20) then
      raise exception 'invalid target' using errcode = '22023';
    end if;
  elsif mode = 'best_of_3' then
    v := '{}';
  elsif mode in ('turns', 'endurance') then
    if quick then raise exception 'mode is friend-only' using errcode = '22023'; end if;
    v := '{}';
  else
    raise exception 'unknown mode' using errcode = '22023';
  end if;
  return v;
end $$;

-- Longest a battle of this mode can run (ms after the start) — used for timeouts.
create or replace function app.battle_max_ms(mode text, variant jsonb) returns bigint
language sql immutable as $$
  select case mode when 'max_reps' then coalesce((variant->>'durationS')::bigint, 60) * 1000
                   when 'speed' then 120000 when 'endurance' then 600000
                   when 'best_of_3' then 3 * 90000 + 2 * 45000 + 30000
                   else 20 * 60000 end
$$;

create or replace function app.create_battle(p_type public.battle_type, p_mode text, p_variant jsonb, p_ranked boolean,
                                             a uuid, b uuid) returns uuid
language plpgsql security definer set search_path = public, app as $$
declare
  v_id uuid;
begin
  insert into public.battles (type, mode, variant, ranked, player_a, player_b, player_a_name, player_b_name, status, season_id)
  values (p_type, p_mode::public.battle_mode, p_variant, p_ranked, a, b,
          (select username from public.profiles where id = a), (select username from public.profiles where id = b),
          'lobby', app.current_season())
  returning id into v_id;
  update public.battles set livekit_room = 'battle-' || v_id where id = v_id;
  return v_id;
end $$;

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
      'b', (select count(*) from public.battle_events e where e.battle_id = b.id and e.user_id = b.player_b)),
    'result', b.result, 'winner', case when b.winner is null then null when b.winner = viewer then 'me' else 'opponent' end,
    'livekitRoom', b.livekit_room, 'createdAt', app.utc_iso(b.created_at))
  from public.battles b where b.id = bid
$$;

create or replace function app.my_battle(bid uuid, me uuid) returns public.battles
language plpgsql stable security definer set search_path = public, app as $$
declare
  v public.battles;
begin
  select * into v from public.battles where id = bid and me in (player_a, player_b);
  if not found then raise exception 'battle not found' using errcode = 'P0002'; end if;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Friend invites (doc 07 §8): to a friend, or a share code anyone can open (friendly only). Expire after 5 min.
-- ---------------------------------------------------------------------------
create or replace function public.create_battle_invite(to_user uuid, mode text, variant jsonb default '{}',
                                                       ranked boolean default false) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_variant jsonb := app.battle_variant(mode, variant, false);
  v_inv public.battle_invites;
begin
  if to_user is not null and not app.are_friends(me, to_user) then
    raise exception 'friends only' using errcode = '42501';
  end if;
  if ranked and to_user is null then raise exception 'ranked invites need a friend' using errcode = '22023'; end if;
  perform app.hit_rate_limit(me, 'battle_invite', 30, interval '1 hour');
  update public.battle_invites set status = 'cancelled'
   where from_user = me and status = 'pending' and battle_invites.to_user is not distinct from create_battle_invite.to_user;
  insert into public.battle_invites (from_user, to_user, code, mode, variant, ranked, expires_at)
  values (me, to_user, substr(md5(random()::text || clock_timestamp()::text), 1, 10), mode::public.battle_mode, v_variant,
          ranked, now() + interval '5 minutes')
  returning * into v_inv;
  if to_user is not null then
    perform app.enqueue_push(to_user, 'battle_invite', 'battles',
      jsonb_build_object('username', (select username from public.profiles where id = me), 'inviteId', v_inv.id, 'mode', mode),
      'invite:' || me);
  end if;
  return jsonb_build_object('id', v_inv.id, 'code', v_inv.code, 'expiresAt', app.utc_iso(v_inv.expires_at),
                            'mode', v_inv.mode, 'variant', v_inv.variant, 'ranked', v_inv.ranked);
end $$;

-- Accept / decline by id (invited friend) or open by share code (anyone, friendly). Returns the battle on accept.
create or replace function public.respond_battle_invite(invite_id uuid, accept boolean, code text default null) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_inv public.battle_invites;
  v_bid uuid;
begin
  select * into v_inv from public.battle_invites i
   where (i.id = invite_id or (respond_battle_invite.code is not null and i.code = respond_battle_invite.code))
   for update;
  if not found or (v_inv.to_user is not null and v_inv.to_user <> me) or v_inv.from_user = me
     or app.is_blocked(me, v_inv.from_user) then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  if v_inv.status <> 'pending' or v_inv.expires_at < now() then
    update public.battle_invites set status = 'expired' where id = v_inv.id and status = 'pending';
    raise exception 'invite expired' using errcode = 'P0001', hint = 'expired';
  end if;
  if not accept then
    update public.battle_invites set status = 'declined' where id = v_inv.id;
    return null;
  end if;
  v_bid := app.create_battle(case when v_inv.ranked then 'friend_ranked' else 'friendly' end::public.battle_type,
                             v_inv.mode::text, v_inv.variant, v_inv.ranked, v_inv.from_user, me);
  update public.battle_invites set status = 'accepted', battle_id = v_bid, to_user = me where id = v_inv.id;
  return app.battle_json(v_bid, me);
end $$;

create or replace function public.cancel_battle_invite(invite_id uuid) returns void
language plpgsql security definer set search_path = public, app as $$
begin
  update public.battle_invites set status = 'cancelled'
   where id = invite_id and from_user = app.require_user() and status = 'pending';
end $$;

create or replace function public.list_battle_invites() returns jsonb
language sql stable security definer set search_path = public, app as $$
  with me as (select app.require_user() id)
  select jsonb_build_object(
    'incoming', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'from', app.user_card(i.from_user, me.id),
                  'mode', i.mode, 'variant', i.variant, 'ranked', i.ranked, 'expiresAt', app.utc_iso(i.expires_at))
                  order by i.created_at desc)
                  from public.battle_invites i, me where i.to_user = me.id and i.status = 'pending' and i.expires_at > now()), '[]'),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'to', case when i.to_user is null then null
                  else app.user_card(i.to_user, me.id) end, 'code', i.code, 'mode', i.mode, 'variant', i.variant,
                  'ranked', i.ranked, 'expiresAt', app.utc_iso(i.expires_at), 'status', i.status, 'battleId', i.battle_id)
                  order by i.created_at desc)
                  from public.battle_invites i, me where i.from_user = me.id and i.created_at > now() - interval '10 minutes'
                   and i.status in ('pending', 'accepted')), '[]'))
$$;

-- ---------------------------------------------------------------------------
-- Live battle (doc 07 §4)
-- ---------------------------------------------------------------------------
create or replace function public.get_battle(battle_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  perform app.my_battle(battle_id, me);
  return app.battle_json(battle_id, me);
end $$;

-- body_ready: when both are ready the countdown starts (3.5 s, doc 07 §4.4).
create or replace function public.battle_ready(battle_id uuid) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v public.battles := app.my_battle(battle_id, me);
begin
  if v.status not in ('lobby', 'ready_check') then return app.battle_json(v.id, me); end if;
  update public.battles b set ready_a = b.ready_a or me = b.player_a, ready_b = b.ready_b or me = b.player_b,
         status = 'ready_check' where b.id = v.id;
  update public.battles b set status = 'countdown', start_at = now() + interval '3500 milliseconds'
   where b.id = v.id and b.ready_a and b.ready_b and b.status = 'ready_check';
  return app.battle_json(v.id, me);
end $$;

-- Batched rep events in server time (ms since start_at): [{"round": 0, "i": 1, "t": 1234, "q": 88}, ...].
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
  select v.id, me, coalesce((r->>'round')::smallint, 0), (r->>'i')::int, (r->>'t')::bigint,
         greatest(0, least(100, coalesce((r->>'q')::int, 0)))::smallint
    from jsonb_array_elements(coalesce(reps, '[]')) r
   where (r->>'t')::bigint between 0 and v_now_ms + 2000              -- no reps from the future (2 s clock slack)
     and (r->>'t')::bigint <= app.battle_max_ms(v.mode::text, v.variant)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  update public.battles b set status = 'live' where b.id = v.id and b.status = 'countdown';
  return v_n;
end $$;

create or replace function public.battle_finish(battle_id uuid) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v public.battles := app.my_battle(battle_id, me);
begin
  if v.status in ('countdown', 'live') then
    update public.battles b set status = 'finished', ended_at = coalesce(b.ended_at, now()) where b.id = v.id;
  end if;
  perform app.settle_battle(v.id, false);
  return app.battle_json(v.id, me);
end $$;

-- Leaving: before the start = cancelled (no trophies); after = loss (doc 07 §4 disconnects).
create or replace function public.battle_forfeit(battle_id uuid) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v public.battles := app.my_battle(battle_id, me);
begin
  if v.status in ('created', 'lobby', 'ready_check') then
    update public.battles b set status = 'cancelled', ended_at = now() where b.id = v.id;
  elsif v.status in ('countdown', 'live', 'finished') then
    perform app.settle_battle(v.id, true, case when me = v.player_a then 'a' else 'b' end);
  end if;
  return app.battle_json(v.id, me);
end $$;

create or replace function public.battle_history(lim int default 30) returns jsonb
language sql stable security definer set search_path = public, app as $$
  with me as (select app.require_user() id)
  select coalesce(jsonb_agg(app.battle_json(b.id, me.id) order by b.created_at desc), '[]')
    from (select b.* from public.battles b, me where me.id in (b.player_a, b.player_b) and b.status in ('settled', 'void')
           order by b.created_at desc limit least(greatest(lim, 1), 100)) b, me
$$;

-- ---------------------------------------------------------------------------
-- Settlement (doc 07 §4.7): result from the server-received rep events, capped by each verified rep log.
-- forfeit_by: 'a' | 'b' — that player left after the start and loses.
-- ---------------------------------------------------------------------------
create or replace function app.battle_reps(v public.battles, uid uuid, out reps jsonb, out flag text)
language plpgsql stable security definer set search_path = public, app as $$
declare
  v_cap int;
  v_any boolean;
begin
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

  -- Ranked friend battles: max 3 counted per pair per UTC day (doc 06 §7).
  v_counted := v.ranked and v.player_a is not null and v.player_b is not null;
  if v_counted and v.type = 'friend_ranked' then
    v_counted := (select count(*) from public.battles x
                   where x.type = 'friend_ranked' and x.status = 'settled' and x.result->>'counted' = 'true'
                     and least(x.player_a, x.player_b) = least(v.player_a, v.player_b)
                     and greatest(x.player_a, x.player_b) = greatest(v.player_a, v.player_b)
                     and x.settled_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') < 3;
  end if;

  if v_counted then
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

-- Battle rep logs carry context.battleId (rep-log.schema.json): link the stored session to its battle (only for a
-- participant) and settle right away when this was the second log.
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
    if found then perform app.settle_battle(v_bid, false); end if;
  end if;
  return new;
end $$;
create trigger rep_session_logs_battle after insert on public.rep_session_logs
  for each row execute function app.on_rep_log_battle();

-- Cron: settle battles whose logs arrived or whose time ran out; cancel stale lobbies.
create or replace function app.settle_due_battles() returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_id uuid;
  v_n int := 0;
begin
  update public.battles set status = 'cancelled', ended_at = now()
   where status in ('lobby', 'ready_check') and created_at < now() - interval '2 minutes';
  for v_id in select id from public.battles where status in ('countdown', 'live', 'finished') loop
    if app.settle_battle(v_id, false) then v_n := v_n + 1; end if;
  end loop;
  update public.battle_invites set status = 'expired' where status = 'pending' and expires_at < now();
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- Matchmaking (doc 07 §3)
-- ---------------------------------------------------------------------------
create or replace function public.matchmaking_join(mode text, region text default 'eu') returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_variant jsonb := app.battle_variant(mode, '{}', true);
  p public.profiles;
begin
  select * into p from public.profiles where id = me;
  if not p.onboarding_completed then raise exception 'finish your profile first' using errcode = '22023'; end if;
  perform app.hit_rate_limit(me, 'matchmaking', 60, interval '1 hour');
  insert into public.matchmaking_queue (user_id, mode, variant, mmr, trust_bucket, region, last_opponent)
  values (me, mode::public.battle_mode, v_variant, p.mmr, case when p.trust_score >= 50 then 1 else 0 end,
          coalesce(nullif(region, ''), 'eu'),
          (select case when b.player_a = me then b.player_b else b.player_a end from public.battles b
            where b.type = 'quick' and me in (b.player_a, b.player_b) and b.created_at > now() - interval '10 minutes'
            order by b.created_at desc limit 1))
  on conflict (user_id) do update set mode = excluded.mode, variant = excluded.variant, mmr = excluded.mmr,
    trust_bucket = excluded.trust_bucket, region = excluded.region, last_opponent = excluded.last_opponent,
    battle_id = null, joined_at = now();
  perform app.run_matchmaking();
  return public.matchmaking_status();
end $$;

create or replace function public.matchmaking_status() returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  q public.matchmaking_queue;
begin
  select * into q from public.matchmaking_queue where user_id = me;
  if not found then return jsonb_build_object('queued', false, 'battle', null); end if;
  if q.battle_id is not null then
    delete from public.matchmaking_queue where user_id = me;
    return jsonb_build_object('queued', false, 'battle', app.battle_json(q.battle_id, me));
  end if;
  if q.joined_at < now() - interval '3 minutes' then
    delete from public.matchmaking_queue where user_id = me;
    return jsonb_build_object('queued', false, 'battle', null, 'timedOut', true);
  end if;
  return jsonb_build_object('queued', true, 'battle', null, 'mode', q.mode,
                            'waitedS', floor(extract(epoch from now() - q.joined_at))::int);
end $$;

create or replace function public.matchmaking_leave() returns void
language sql security definer set search_path = public, app as $$
  delete from public.matchmaking_queue where user_id = app.require_user() and battle_id is null
$$;

-- MMR window: ±100 at 0 s, +50 every 5 s, max ±400; other regions after 20 s; never last opponent; same trust bucket.
create or replace function app.mm_window(waited_s double precision) returns double precision
language sql immutable as $$ select least(400, 100 + 50 * floor(greatest(waited_s, 0) / 5)) $$;

create or replace function app.run_matchmaking(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  q record;
  o record;
  v_bid uuid;
  v_n int := 0;
begin
  delete from public.matchmaking_queue where battle_id is null and joined_at < now_at - interval '3 minutes';
  for q in select * from public.matchmaking_queue where battle_id is null order by joined_at for update skip locked loop
    continue when exists (select 1 from public.matchmaking_queue x where x.user_id = q.user_id and x.battle_id is not null);
    select x.* into o from public.matchmaking_queue x
     where x.battle_id is null and x.user_id <> q.user_id and x.mode = q.mode and x.trust_bucket = q.trust_bucket
       and x.user_id is distinct from q.last_opponent and q.user_id is distinct from x.last_opponent
       and abs(x.mmr - q.mmr) <= app.mm_window(extract(epoch from now_at - least(x.joined_at, q.joined_at)))
       and (x.region = q.region or now_at - least(x.joined_at, q.joined_at) >= interval '20 seconds')
       and not app.is_blocked(x.user_id, q.user_id)
     order by (x.region = q.region) desc, abs(x.mmr - q.mmr), x.joined_at
     limit 1;
    continue when not found;
    v_bid := app.create_battle('quick', q.mode::text, q.variant, true, q.user_id, o.user_id);
    update public.matchmaking_queue set battle_id = v_bid where user_id in (q.user_id, o.user_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- Seasons rollover (doc 08 §2.5): soft reset above 2000, floors cleared, ledger entries.
-- ---------------------------------------------------------------------------
create or replace function app.rollover_season(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_new smallint := app.current_season(now_at);
  v_n int;
begin
  if not exists (select 1 from public.seasons where status = 'active' and id <> v_new) then return 0; end if;
  update public.seasons set status = 'closed' where status = 'active' and id <> v_new;
  insert into public.trophy_ledger (user_id, delta, balance_after, reason, season_id)
  select id, app.season_reset(trophies) - trophies, app.season_reset(trophies), 'season_reset', v_new
    from public.profiles where trophies > 2000;
  get diagnostics v_n = row_count;
  update public.profiles set trophies = app.season_reset(trophies), trophy_floor = 0 where trophies > 0 or trophy_floor > 0;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- Battles leaderboard (doc 08 §4): trophies in the current season.
-- ---------------------------------------------------------------------------
create or replace function app.board_periods(board text) returns text[]
language sql immutable as $$
  select case board when 'wake' then array['week', 'month', 'all'] when 'streak' then array['current']
                    when 'reps' then array['day', 'week', 'month', 'all'] when 'battles' then array['season'] end
$$;

create or replace function app.period_key(period text, at_ts timestamptz default now()) returns text
language sql stable as $$
  select case period
    when 'day' then to_char(at_ts at time zone 'UTC', 'YYYY-MM-DD')
    when 'week' then to_char(at_ts at time zone 'UTC', 'IYYY-"W"IW')
    when 'month' then to_char(at_ts at time zone 'UTC', 'YYYY-MM')
    when 'season' then 'season-' || app.season_id_for(at_ts)
    when 'all' then 'all' when 'current' then 'current' end
$$;

create or replace function app.board_scores(board text, period text, at_ts timestamptz default now())
returns table (user_id uuid, score bigint, tiebreak bigint)
language plpgsql stable security definer set search_path = public, app as $$
declare
  v_day date := (at_ts at time zone 'UTC')::date;
  v_wk date := (date_trunc('week', at_ts at time zone 'UTC'))::date;
  v_mo date := (date_trunc('month', at_ts at time zone 'UTC'))::date;
begin
  if board = 'wake' and period = 'week' then
    return query select s.user_id, s.wake_points::bigint, 0::bigint from public.user_stats_weekly s where s.week_start = v_wk and s.wake_points > 0;
  elsif board = 'wake' and period = 'month' then
    return query select s.user_id, s.wake_points::bigint, 0::bigint from public.user_stats_monthly s where s.month = v_mo and s.wake_points > 0;
  elsif board = 'wake' and period = 'all' then
    return query select s.user_id, s.wake_points, 0::bigint from public.user_stats_alltime s where s.wake_points > 0;
  elsif board = 'streak' and period = 'current' then
    return query select s.user_id, s.pure_current::bigint, s.pure_best::bigint from public.streaks s where s.pure_current > 0;
  elsif board = 'reps' and period = 'day' then
    return query select s.user_id, s.reps_total::bigint, 0::bigint from public.user_stats_daily s where s.day = v_day and s.reps_total > 0;
  elsif board = 'reps' and period = 'week' then
    return query select s.user_id, s.reps_total::bigint, 0::bigint from public.user_stats_weekly s where s.week_start = v_wk and s.reps_total > 0;
  elsif board = 'reps' and period = 'month' then
    return query select s.user_id, s.reps_total::bigint, 0::bigint from public.user_stats_monthly s where s.month = v_mo and s.reps_total > 0;
  elsif board = 'reps' and period = 'all' then
    return query select s.user_id, s.reps_competitive, 0::bigint from public.user_stats_alltime s where s.reps_competitive > 0;
  elsif board = 'battles' and period = 'season' then
    -- tiebreak: the earlier one reached the score ranks higher → use the negated time of the last ledger entry
    return query select p.id, p.trophies::bigint,
                        -coalesce((select extract(epoch from max(l.created_at))::bigint from public.trophy_ledger l where l.user_id = p.id), 0)
                   from public.profiles p where p.trophies > 0;
  else
    raise exception 'unknown board % / period %', board, period using errcode = '22023';
  end if;
end $$;

create or replace function app.refresh_leaderboards(at_ts timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_board text;
  v_period text;
  v_key text;
  v_rows int := 0;
  v_n int;
begin
  for v_board in select unnest(array['wake', 'streak', 'reps', 'battles']) loop
    foreach v_period in array app.board_periods(v_board) loop
      v_key := app.period_key(v_period, at_ts);
      delete from public.leaderboard_snapshots s where s.board = v_board and s.period_key = v_key;
      delete from public.leaderboard_snapshots s where s.board = v_board and s.refreshed_at < at_ts - interval '8 days';
      insert into public.leaderboard_snapshots (board, scope, scope_key, period_key, pos, rank, user_id, score, refreshed_at)
      select v_board, 'global', '', v_key, r.rn, r.rank, r.user_id, r.score, at_ts
        from (select x.*, row_number() over (order by x.rank, x.user_id) rn from app.board_ranked(v_board, v_period, at_ts) x) r
       where r.rn <= 1000;
      get diagnostics v_n = row_count;
      v_rows := v_rows + v_n;
      insert into public.leaderboard_snapshots (board, scope, scope_key, period_key, pos, rank, user_id, score, refreshed_at)
      select v_board, 'country', r.country, v_key, r.rn, r.crank, r.user_id, r.score, at_ts
        from (select x.*, rank() over (partition by x.country order by x.score desc, x.tiebreak desc) crank,
                     row_number() over (partition by x.country order by x.score desc, x.tiebreak desc, x.user_id) rn
                from app.board_ranked(v_board, v_period, at_ts) x where x.country is not null) r
       where r.rn <= 1000;
      get diagnostics v_n = row_count;
      v_rows := v_rows + v_n;
    end loop;
  end loop;
  return v_rows;
end $$;

-- ---------------------------------------------------------------------------
-- Grants + cron
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['create_battle_invite(uuid, text, jsonb, boolean)', 'respond_battle_invite(uuid, boolean, text)',
                           'cancel_battle_invite(uuid)', 'list_battle_invites()', 'get_battle(uuid)', 'battle_ready(uuid)',
                           'battle_push_rep(uuid, jsonb)', 'battle_finish(uuid)', 'battle_forfeit(uuid)', 'battle_history(int)',
                           'matchmaking_join(text, text)', 'matchmaking_status()', 'matchmaking_leave()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
grant execute on all functions in schema app to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then return; end if;
  perform cron.schedule('pushly-matchmaking', '2 seconds', 'select app.run_matchmaking()');
  perform cron.schedule('pushly-settle-battles', '5 seconds', 'select app.settle_due_battles()');
  perform cron.schedule('pushly-season-rollover', '5 0 1 * *', 'select app.rollover_season()');
end $$;
