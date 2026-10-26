-- 0032 — D-076: everyone on the trophy board (also 0 trophies), Clan Wars from the first member.
--
-- * Board `battles` (trophies): every finished profile, not only those above 0 — an empty board with players in the
--   game looked broken. Snapshots refresh every minute (migration 0013).
-- * Clan Wars: any clan with war on joins Monday's matchmaking, even a one-person clan (was ≥ 5 members). Pairing is
--   unchanged: similar number of active members (±20 %) first, then the closest rating.

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
                   from public.profiles p where p.onboarding_completed;
  else
    raise exception 'unknown board % / period %', board, period using errcode = '22023';
  end if;
end $$;


-- Clan War matchmaking (0015) with no minimum clan size.
create or replace function app.clan_war_matchmake(week date default app.war_week_start()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  c record;
  o record;
  v_id uuid;
  v_n int := 0;
begin
  create temp table if not exists tmp_war_pool (clan_id uuid primary key, active int, rating int, last_opp uuid, taken boolean)
    on commit drop;
  delete from tmp_war_pool;
  insert into tmp_war_pool
  select cl.id,
         (select count(distinct m.user_id) from public.clan_members m join public.rep_sessions s on s.user_id = m.user_id
           where m.clan_id = cl.id and s.verified and s.started_at >= week::timestamp at time zone 'UTC' - interval '7 days'),
         cl.rating,
         (select case when w.clan_a = cl.id then w.clan_b else w.clan_a end from public.clan_wars w
           where w.week_start = week - 7 and cl.id in (w.clan_a, w.clan_b) limit 1),
         false
    from public.clans cl
   where cl.war_enabled and cl.member_count >= 1
     and not exists (select 1 from public.clan_wars w where w.week_start = week and cl.id in (w.clan_a, w.clan_b));
  for c in select * from tmp_war_pool order by active desc, rating desc loop
    continue when (select taken from tmp_war_pool where clan_id = c.clan_id);
    select * into o from tmp_war_pool x
     where not x.taken and x.clan_id <> c.clan_id and x.clan_id is distinct from c.last_opp
       and x.active between floor(c.active * 0.8) and ceil(c.active * 1.2)
     order by abs(x.rating - c.rating), x.clan_id limit 1;
    if not found then        -- no clan of similar size: closest rating among the rest
      select * into o from tmp_war_pool x
       where not x.taken and x.clan_id <> c.clan_id and x.clan_id is distinct from c.last_opp
       order by abs(x.active - c.active), abs(x.rating - c.rating), x.clan_id limit 1;
    end if;
    update tmp_war_pool set taken = true where clan_id in (c.clan_id, o.clan_id);
    insert into public.clan_wars (week_start, clan_a, clan_b, status) values (week, c.clan_id, o.clan_id, 'live')
    returning id into v_id;
    insert into public.clan_war_rosters (war_id, clan_id, user_id)
    select v_id, m.clan_id, m.user_id from public.clan_members m where m.clan_id in (c.clan_id, o.clan_id);
    v_n := v_n + 1;
    perform app.clan_system_message(x, 'The Clan War has started!', jsonb_build_object('event', 'war_started', 'warId', v_id))
      from unnest(array[c.clan_id, o.clan_id]) x where x is not null;
  end loop;
  return v_n;
end $$;


grant execute on all functions in schema app to service_role;
