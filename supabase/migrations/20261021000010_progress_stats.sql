-- 0010 — progress: XP, levels, achievements (doc 10 §4–5) + the stats RPC (doc 10 §1–2), roadmap P5-01 / P5-04.
-- Rules: tools/reference/pushly_ref/progress.py, vectors shared/test-vectors/progress (tested by 061_*); definitions:
-- shared/achievements/definitions.json (062_* checks the table matches it). Clients never write any of this.

create table public.achievement_definitions (
  id text primary key,
  group_name text not null,
  title text not null,
  description text not null,
  icon text not null,
  tier smallint not null default 1,
  rule jsonb not null,
  xp int not null default 0,
  streak_freezes smallint not null default 0,
  sort int not null default 0,
  active boolean not null default true
);

create table public.user_achievements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id text not null references public.achievement_definitions(id),
  session_id uuid,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

alter table public.achievement_definitions enable row level security;
alter table public.user_achievements enable row level security;
revoke insert, update, delete, truncate on public.achievement_definitions, public.user_achievements from anon, authenticated;
revoke all on public.user_achievements from anon;
create policy achievement_definitions_read on public.achievement_definitions for select to anon, authenticated using (true);
create policy user_achievements_select_own on public.user_achievements for select to authenticated using (user_id = auth.uid());

-- Generated from shared/achievements/definitions.json (supabase/tests/062_* keeps them in sync).
insert into public.achievement_definitions (id, group_name, title, description, icon, tier, rule, xp, streak_freezes, sort) values
  ('first_wake', 'wake', 'First Wake', 'Beat your first wake-up challenge.', 'sunrise', 1, '{"type":"wakes","min":1}'::jsonb, 50, 0, 1),
  ('wake_7', 'wake', 'Seven Mornings', 'Beat 7 wake-up challenges.', 'sun.max', 1, '{"type":"wakes","min":7}'::jsonb, 100, 0, 2),
  ('wake_30', 'wake', 'Morning Person', 'Beat 30 wake-up challenges.', 'sun.max.fill', 2, '{"type":"wakes","min":30}'::jsonb, 250, 1, 3),
  ('wake_100', 'wake', 'Sunrise Machine', 'Beat 100 wake-up challenges.', 'sun.horizon.fill', 3, '{"type":"wakes","min":100}'::jsonb, 600, 1, 4),
  ('wake_365', 'wake', 'Year of Mornings', 'Beat 365 wake-up challenges.', 'crown.fill', 4, '{"type":"wakes","min":365}'::jsonb, 2000, 2, 5),
  ('early_bird', 'wake', 'Early Bird', 'Beat 10 challenges that rang before 6:00.', 'bird', 2, '{"type":"wakes_before","localTime":"06:00","min":10}'::jsonb, 300, 0, 6),
  ('dawn_patrol', 'wake', 'Dawn Patrol', 'Beat 30 challenges that rang before 6:00.', 'moon.stars.fill', 3, '{"type":"wakes_before","localTime":"06:00","min":30}'::jsonb, 800, 0, 7),
  ('streak_3', 'wake', 'On a Roll', 'Reach a 3-day wake streak.', 'flame', 1, '{"type":"streak","min":3}'::jsonb, 60, 0, 8),
  ('streak_7', 'wake', 'Week Strong', 'Reach a 7-day wake streak.', 'flame.fill', 2, '{"type":"streak","min":7}'::jsonb, 150, 0, 9),
  ('streak_30', 'wake', 'Iron Morning', 'Reach a 30-day wake streak.', 'shield.fill', 3, '{"type":"streak","min":30}'::jsonb, 600, 1, 10),
  ('streak_100', 'wake', 'Unbreakable', 'Reach a 100-day wake streak.', 'bolt.shield.fill', 4, '{"type":"streak","min":100}'::jsonb, 2000, 2, 11),
  ('hard_mode', 'wake', 'No Snooze Needed', 'Beat 10 challenges in Sprint, Sets or Beat the Clock.', 'timer', 2, '{"type":"wakes_mode","modes":["sprint","sets","beatTheClock"],"min":10}'::jsonb, 300, 0, 12),
  ('reps_100', 'volume', 'First Hundred', 'Do 100 push-ups in total.', 'figure.strengthtraining.traditional', 1, '{"type":"reps_total","min":100}'::jsonb, 50, 0, 13),
  ('reps_500', 'volume', 'Five Hundred', 'Do 500 push-ups in total.', 'figure.strengthtraining.traditional', 1, '{"type":"reps_total","min":500}'::jsonb, 100, 0, 14),
  ('reps_1k', 'volume', '1K Club', 'Do 1,000 push-ups in total.', '1.circle.fill', 2, '{"type":"reps_total","min":1000}'::jsonb, 200, 0, 15),
  ('reps_2500', 'volume', 'Quarter Ten', 'Do 2,500 push-ups in total.', '2.circle.fill', 2, '{"type":"reps_total","min":2500}'::jsonb, 300, 0, 16),
  ('reps_5k', 'volume', '5K Grinder', 'Do 5,000 push-ups in total.', '5.circle.fill', 3, '{"type":"reps_total","min":5000}'::jsonb, 500, 0, 17),
  ('reps_10k', 'volume', '10K Legend', 'Do 10,000 push-ups in total.', 'star.circle.fill', 3, '{"type":"reps_total","min":10000}'::jsonb, 1000, 0, 18),
  ('reps_25k', 'volume', '25K Titan', 'Do 25,000 push-ups in total.', 'star.fill', 4, '{"type":"reps_total","min":25000}'::jsonb, 2000, 0, 19),
  ('reps_50k', 'volume', '50K Mythic', 'Do 50,000 push-ups in total.', 'sparkles', 4, '{"type":"reps_total","min":50000}'::jsonb, 4000, 0, 20),
  ('reps_100k', 'volume', '100K Immortal', 'Do 100,000 push-ups in total.', 'crown.fill', 5, '{"type":"reps_total","min":100000}'::jsonb, 8000, 0, 21),
  ('day_50', 'volume', 'Big Day', 'Do 50 push-ups in one day.', 'calendar', 1, '{"type":"reps_day","min":50}'::jsonb, 80, 0, 22),
  ('century', 'volume', 'Century', 'Do 100 push-ups in one day.', 'calendar.badge.plus', 2, '{"type":"reps_day","min":100}'::jsonb, 200, 0, 23),
  ('day_250', 'volume', 'Marathon Day', 'Do 250 push-ups in one day.', 'calendar.badge.exclamationmark', 3, '{"type":"reps_day","min":250}'::jsonb, 500, 0, 24),
  ('set_25', 'volume', 'Quarter Set', 'Do 25 push-ups in one set.', '25.circle', 1, '{"type":"best_set","min":25}'::jsonb, 100, 0, 25),
  ('set_50', 'volume', 'Half Century', 'Do 50 push-ups in one set.', '50.circle', 2, '{"type":"best_set","min":50}'::jsonb, 300, 0, 26),
  ('set_100', 'volume', 'Hundred Straight', 'Do 100 push-ups in one set.', '100.circle', 4, '{"type":"best_set","min":100}'::jsonb, 1000, 0, 27),
  ('sessions_10', 'volume', 'Regular', 'Finish 10 sessions.', 'checkmark.circle', 1, '{"type":"sessions","min":10}'::jsonb, 80, 0, 28),
  ('sessions_100', 'volume', 'Habit', 'Finish 100 sessions.', 'checkmark.seal.fill', 3, '{"type":"sessions","min":100}'::jsonb, 500, 0, 29),
  ('textbook', 'form', 'Textbook', 'Finish a session of 10+ push-ups with average form 90 or better.', 'graduationcap.fill', 2, '{"type":"session_quality","minReps":10,"avgMin":90}'::jsonb, 200, 0, 30),
  ('perfect_ten', 'form', 'Perfect Ten', 'Finish a session of 10+ push-ups with average form 95 or better.', '10.circle.fill', 3, '{"type":"session_quality","minReps":10,"avgMin":95}'::jsonb, 400, 0, 31),
  ('clean_fifty', 'form', 'Clean Fifty', 'Finish a session of 50+ push-ups with average form 85 or better.', 'sparkles', 3, '{"type":"session_quality","minReps":50,"avgMin":85}'::jsonb, 600, 0, 32),
  ('level_5', 'progress', 'Level 5', 'Reach level 5.', '5.square.fill', 1, '{"type":"level","min":5}'::jsonb, 0, 0, 33),
  ('level_10', 'progress', 'Level 10', 'Reach level 10.', '10.square.fill', 2, '{"type":"level","min":10}'::jsonb, 0, 0, 34),
  ('level_20', 'progress', 'Level 20', 'Reach level 20.', '20.square.fill', 3, '{"type":"level","min":20}'::jsonb, 0, 0, 35),
  ('first_blood', 'battles', 'First Blood', 'Win your first battle.', 'bolt.fill', 1, '{"type":"battle_wins","min":1}'::jsonb, 100, 0, 36),
  ('hat_trick', 'battles', 'Hat-trick', 'Win 3 battles in a row.', '3.circle.fill', 2, '{"type":"battle_win_streak","min":3}'::jsonb, 250, 0, 37),
  ('mode_master', 'battles', 'Mode Master', 'Win at least once in every battle mode.', 'square.grid.3x3.fill', 3, '{"type":"battle_modes_won","min":5}'::jsonb, 500, 0, 38),
  ('giant_slayer', 'battles', 'Giant Slayer', 'Beat someone with 500+ more trophies.', 'figure.martial.arts', 3, '{"type":"battle_upset","trophyGap":500}'::jsonb, 500, 0, 39),
  ('team_player', 'clans', 'Team Player', 'Take part in your first Clan War.', 'person.3.fill', 1, '{"type":"clan_wars","min":1}'::jsonb, 100, 0, 40),
  ('war_mvp', 'clans', 'MVP', 'Be your clan''s top scorer in a Clan War.', 'medal.fill', 3, '{"type":"clan_war_mvp","min":1}'::jsonb, 500, 0, 41),
  ('war_machine', 'clans', 'War Machine', 'Win 10 Clan Wars.', 'flag.checkered', 4, '{"type":"clan_war_wins","min":10}'::jsonb, 1000, 0, 42),
  ('squad', 'social', 'Squad', 'Have 5 friends on Pushly.', 'person.2.fill', 1, '{"type":"friends","min":5}'::jsonb, 100, 0, 43),
  ('recruiter', 'social', 'Recruiter', 'Invite 3 friends who join.', 'envelope.open.fill', 2, '{"type":"invites_joined","min":3}'::jsonb, 300, 1, 44)
on conflict (id) do update set group_name = excluded.group_name, title = excluded.title,
  description = excluded.description, icon = excluded.icon, tier = excluded.tier, rule = excluded.rule, xp = excluded.xp,
  streak_freezes = excluded.streak_freezes, sort = excluded.sort;

-- ---------------------------------------------------------------------------
-- Levels (mirror of progress.py)
-- ---------------------------------------------------------------------------
create or replace function app.level_threshold(lvl int) returns bigint
language sql immutable as $$ select floor(100 * power(greatest(lvl - 1, 0), 1.5) + 0.5)::bigint $$;

create or replace function app.level_for_xp(xp bigint) returns int
language plpgsql immutable as $$
declare lvl int := 1;
begin
  while lvl < 200 and app.level_threshold(lvl + 1) <= xp loop lvl := lvl + 1; end loop;
  return lvl;
end $$;

create or replace function app.level_progress(xp bigint) returns jsonb
language sql immutable as $$
  select jsonb_build_object('level', l, 'xpIntoLevel', xp - app.level_threshold(l),
                            'xpForNext', app.level_threshold(l + 1) - app.level_threshold(l))
  from (select app.level_for_xp(xp) l) x
$$;

-- ---------------------------------------------------------------------------
-- Achievement rules (mirror of progress.rule_met)
-- ---------------------------------------------------------------------------
create or replace function app.rule_met(rule jsonb, facts jsonb) returns boolean
language plpgsql immutable as $$
declare
  t text := rule->>'type';
  n numeric;
begin
  case t
    when 'wakes' then n := coalesce((facts->>'wakes')::numeric, 0);
    when 'wakes_before' then n := coalesce((facts->'wakesBefore'->>(rule->>'localTime'))::numeric, 0);
    when 'wakes_mode' then
      select coalesce(sum((facts->'wakesByMode'->>m)::numeric), 0) into n
        from jsonb_array_elements_text(rule->'modes') m;
    when 'streak' then n := coalesce((facts->>'bestStreak')::numeric, 0);
    when 'reps_total' then n := coalesce((facts->>'repsTotal')::numeric, 0);
    when 'reps_day' then n := coalesce((facts->>'maxDay')::numeric, 0);
    when 'best_set' then n := coalesce((facts->>'bestSet')::numeric, 0);
    when 'sessions' then n := coalesce((facts->>'sessions')::numeric, 0);
    when 'session_quality' then
      return coalesce((facts->'bestAvgByMinReps'->>(rule->>'minReps'))::numeric, 0) >= (rule->>'avgMin')::numeric;
    when 'level' then n := coalesce((facts->>'level')::numeric, 1);
    else return false;   -- battle_*, clan_*, friends, invites_joined: later phases
  end case;
  return n >= (rule->>'min')::numeric;
end $$;

create or replace function app.achievements_unlocked(facts jsonb, already text[]) returns text[]
language sql stable as $$
  select coalesce(array_agg(id order by sort), '{}') from public.achievement_definitions
   where active and not (id = any(coalesce(already, '{}'))) and app.rule_met(rule, facts)
$$;

-- Facts about a user for the rules — verified sessions only.
create or replace function app.user_facts(uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  tz text;
  f jsonb;
  times jsonb := '{}';
  quality jsonb := '{}';
  t text;
  r int;
  v numeric;
begin
  select coalesce(timezone, 'UTC') into tz from public.profiles where id = uid;
  for t in select distinct rule->>'localTime' from public.achievement_definitions where rule->>'type' = 'wakes_before' loop
    select count(*) into v from public.wake_attempts
     where user_id = uid and status = 'succeeded' and (scheduled_at at time zone tz)::time < t::time;
    times := times || jsonb_build_object(t, v);
  end loop;
  for r in select distinct (rule->>'minReps')::int from public.achievement_definitions where rule->>'type' = 'session_quality' loop
    select coalesce(max(avg_quality), 0) into v from public.rep_sessions
     where user_id = uid and verified and reps_counted >= r;
    quality := quality || jsonb_build_object(r::text, v);
  end loop;
  select jsonb_build_object(
    'wakes', (select count(*) from public.wake_attempts where user_id = uid and status = 'succeeded'),
    'wakesBefore', times,
    'wakesByMode', coalesce((select jsonb_object_agg(m, c) from (
        select mode->>'type' m, count(*) c from public.wake_attempts
         where user_id = uid and status = 'succeeded' and mode is not null group by 1) x), '{}'),
    'bestStreak', coalesce((select best from public.streaks where user_id = uid), 0),
    'repsTotal', coalesce((select sum(reps_counted) from public.rep_sessions where user_id = uid and verified), 0),
    'maxDay', coalesce((select max(n) from (select sum(reps_counted) n from public.rep_sessions
                          where user_id = uid and verified group by (started_at at time zone tz)::date) d), 0),
    'bestSet', coalesce((select max(best_set) from public.rep_sessions where user_id = uid and verified), 0),
    'sessions', (select count(*) from public.rep_sessions where user_id = uid and verified),
    'bestAvgByMinReps', quality,
    'level', (select level from public.profiles where id = uid)) into f;
  return f;
end $$;

-- Adds XP, unlocks achievements (their XP + streak freezes), updates the level. Returns what the result screen shows.
create or replace function app.award_progress(uid uuid, sid uuid, xp_gain int) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  before_level int;
  new_ids text[];
  more text[];
  total_xp bigint;
  tz text;
  unlocked jsonb := '[]';
begin
  select level, coalesce(timezone, 'UTC') into before_level, tz from public.profiles where id = uid for update;
  update public.profiles set xp = xp + greatest(xp_gain, 0) where id = uid;
  update public.profiles set level = app.level_for_xp(xp) where id = uid;
  new_ids := app.achievements_unlocked(app.user_facts(uid),
               (select coalesce(array_agg(achievement_id), '{}') from public.user_achievements where user_id = uid));
  if cardinality(new_ids) > 0 then
    insert into public.user_achievements (user_id, achievement_id, session_id)
    select uid, unnest(new_ids), sid on conflict do nothing;
    update public.profiles set xp = xp + (select coalesce(sum(xp), 0) from public.achievement_definitions where id = any(new_ids))
     where id = uid;
    update public.profiles set level = app.level_for_xp(xp) where id = uid;
    insert into public.streak_freeze_grants (user_id, granted_on, count, source)
    select uid, (now() at time zone tz)::date, least(streak_freezes, 2), 'achievement:' || id
      from public.achievement_definitions where id = any(new_ids) and streak_freezes > 0;
    -- Level achievements can follow from the XP just added (they give no XP themselves, so one more pass is enough).
    more := app.achievements_unlocked(app.user_facts(uid),
              (select coalesce(array_agg(achievement_id), '{}') from public.user_achievements where user_id = uid));
    if cardinality(more) > 0 then
      insert into public.user_achievements (user_id, achievement_id, session_id)
      select uid, unnest(more), sid on conflict do nothing;
      new_ids := new_ids || more;
    end if;
    perform app.recompute_streak(uid);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'description', description, 'icon', icon,
                                               'tier', tier, 'xp', xp) order by sort), '[]')
    into unlocked from public.achievement_definitions where id = any(new_ids);
  select xp into total_xp from public.profiles where id = uid;
  return app.level_progress(total_xp) || jsonb_build_object('xp', total_xp, 'xpGained', xp_gain,
    'levelUp', app.level_for_xp(total_xp) > before_level, 'newAchievements', unlocked);
end $$;

-- Applies one validated rep session (called by the Edge Function with the service role). Idempotent by sessionId.
-- p: {userId, deviceId, receivedAt, verified, verification, flags:[{type,severity,details}], log, signature,
--     session: {sessionId, context, occurrenceId, startedAt, endedAt (epoch ms), ringAt, outcome, snoozes,
--               reps:[{tStart,tEnd,quality}], sets, sprintStart, rejected, specVersion, appVersion, platform, bestSet}}
create or replace function app.apply_validated_session(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := (p->>'userId')::uuid;
  s jsonb := p->'session';
  sid uuid := (s->>'sessionId')::uuid;
  existing record;
  received timestamptz := coalesce((p->>'receivedAt')::timestamptz, now());
  started timestamptz := to_timestamp((s->>'startedAt')::bigint / 1000.0);
  ended timestamptz := to_timestamp((s->>'endedAt')::bigint / 1000.0);
  late_h numeric := extract(epoch from (received - ended)) / 3600;
  v_verified boolean := coalesce((p->>'verified')::boolean, false);
  v_verification jsonb := coalesce(p->'verification', '{}');
  v_reps int := jsonb_array_length(coalesce(s->'reps', '[]'));
  avg_q int;
  v_best_set int := coalesce((s->>'bestSet')::int, 0);
  tz text;
  local_d date;
  ctx text := s->>'context';
  occ_alarm uuid;
  occ_date date;
  plan jsonb;
  decision jsonb;
  attempt record;
  wake_result jsonb;
  v_points int := 0;
  prev_best int;
  sessions_before int;
  day_reps int;
  week_reps int;
  f jsonb;
  v_result jsonb;
  xp_gain int := 0;
  progress jsonb;
  new_best boolean := false;
  st jsonb;
begin
  select * into existing from public.rep_sessions where id = sid;
  if found then
    if existing.user_id <> uid then raise exception 'session_conflict' using errcode = 'P0409'; end if;
    return existing.result;
  end if;
  select coalesce(timezone, 'UTC') into tz from public.profiles where id = uid;
  if tz is null then raise exception 'unknown_user' using errcode = 'P0404'; end if;
  local_d := (started at time zone tz)::date;
  select round(avg((r->>'quality')::int)) into avg_q from jsonb_array_elements(coalesce(s->'reps', '[]')) r;

  -- Server-side soft checks that need history (doc 06 §4).
  select coalesce(sum(reps_total), 0) into day_reps from public.user_stats_daily
   where user_id = uid and day = (started at time zone 'UTC')::date;
  select coalesce(sum(reps_total), 0) into week_reps from public.user_stats_weekly
   where user_id = uid and week_start = (date_trunc('week', started at time zone 'UTC'))::date;
  if v_verified and (day_reps + v_reps > 1000 or week_reps + v_reps > 5000) then
    v_verified := false;
    v_verification := v_verification || '{"hold": "volume_ceiling"}';
    p := jsonb_set(p, '{flags}', coalesce(p->'flags', '[]') || jsonb_build_object('type', 'volume_ceiling',
         'severity', 'soft', 'details', jsonb_build_object('dayReps', day_reps, 'weekReps', week_reps, 'reps', v_reps)));
  end if;
  select value into prev_best from public.personal_records where user_id = uid and record = 'best_set';
  select count(*) into sessions_before from public.rep_sessions where user_id = uid and rep_sessions.verified;
  if v_verified and sessions_before >= 10 and prev_best is not null and v_best_set > prev_best * 1.8 then
    p := jsonb_set(p, '{flags}', coalesce(p->'flags', '[]') || jsonb_build_object('type', 'personal_best_jump',
         'severity', 'soft', 'details', jsonb_build_object('previous', prev_best, 'bestSet', v_best_set)));
  end if;

  insert into public.rep_sessions (id, user_id, device_id, context, occurrence_id, started_at, ended_at,
    reps_counted, best_set, avg_quality, rejected, spec_version, app_version, platform, verified, verification,
    late, received_at)
  values (sid, uid, (p->>'deviceId')::uuid, ctx::public.session_context, s->>'occurrenceId', started, ended, v_reps,
    v_best_set, avg_q, coalesce(s->'rejected', '{}'), (s->>'specVersion')::smallint, s->>'appVersion',
    (s->>'platform')::public.platform_t, v_verified, v_verification, late_h > 48, received);
  begin
    insert into public.rep_session_logs (session_id, log, signature)
    values (sid, coalesce(p->'log', '{}'), coalesce(p->>'signature', 'unsigned:' || sid::text));
  exception when unique_violation then
    raise exception 'duplicate_log' using errcode = 'P0409';
  end;
  for f in select * from jsonb_array_elements(coalesce(p->'flags', '[]')) loop
    insert into public.anti_cheat_flags (user_id, session_id, type, severity, details)
    values (uid, sid, f->>'type', (f->>'severity')::public.flag_severity, f->'details');
  end loop;

  -- Wake challenge: only verified, on-time (≤ 48 h) sessions for today's challenge occurrence (doc 06 §5).
  if ctx = 'wake' and v_verified and late_h <= 48 and s->>'occurrenceId' ~ '^[0-9a-fA-F-]{36}:\d{4}-\d{2}-\d{2}$' then
    occ_alarm := split_part(s->>'occurrenceId', ':', 1)::uuid;
    occ_date := split_part(s->>'occurrenceId', ':', 2)::date;
    plan := app.day_plan(uid, occ_date, tz);
    if plan->>'kind' = 'ring' and (plan->>'alarmId')::uuid = occ_alarm then
      decision := app.decide_wake(plan->'mode', (extract(epoch from (plan->>'t0')::timestamptz) * 1000)::bigint,
                                  (extract(epoch from received) * 1000)::bigint, s);
      insert into public.wake_attempts (user_id, local_date, occurrence_id, alarm_id, alarm_version, scheduled_at,
                                        deadline_at, mode, status)
      values (uid, occ_date, plan->>'occurrenceId', occ_alarm, (plan->>'version')::int, (plan->>'t0')::timestamptz,
              (plan->>'deadline')::timestamptz, plan->'mode', 'scheduled')
      on conflict (user_id, local_date) do nothing;
      select * into attempt from public.wake_attempts where user_id = uid and local_date = occ_date for update;
      -- succeeded is final; failed / missed only give way to a proven success; in_progress never overrides a result.
      if attempt.status <> 'succeeded' and (
           decision->>'status' = 'succeeded'
           or (decision->>'status' in ('failed', 'missed') and attempt.status in ('scheduled', 'ringing', 'in_progress'))
           or (decision->>'status' = 'in_progress' and attempt.status in ('scheduled', 'ringing'))) then
        if decision->>'status' = 'succeeded' then
          v_points := app.wake_points((decision->>'finalTargetReps')::int, plan->'mode'->>'type',
                                    (decision->>'snoozesUsed')::int, coalesce(avg_q, 0));
        end if;
        update public.wake_attempts set status = (decision->>'status')::public.wake_status,
          reason = decision->>'reason', session_id = sid, final_target_reps = (decision->>'finalTargetReps')::int,
          snoozes_used = (decision->>'snoozesUsed')::int, score = (decision->>'score')::int, points = v_points,
          decided_at = case when decision->>'status' = 'in_progress' then null else received end
        where id = attempt.id;
        if v_points > 0 then
          perform app.bump_stats(uid, (plan->>'t0')::timestamptz, null, null, 0, 0, null, v_points, true);
          xp_gain := xp_gain + 20;   -- succeeded wake (doc 10 §5)
        end if;
      end if;
      select * into attempt from public.wake_attempts where id = attempt.id;
      wake_result := jsonb_build_object('occurrenceId', plan->>'occurrenceId', 'status', attempt.status,
        'reason', attempt.reason, 'points', attempt.points, 'finalTargetReps', attempt.final_target_reps,
        'score', attempt.score, 'deadline', plan->>'deadline');
    else
      wake_result := jsonb_build_object('occurrenceId', s->>'occurrenceId', 'status', 'not_challenge',
                                        'reason', 'not_todays_challenge_occurrence');
    end if;
  end if;

  perform app.bump_stats(uid, started, local_d, ctx, v_reps, v_best_set, avg_q, 0, v_verified and late_h <= 48);
  if v_verified and v_best_set > coalesce(prev_best, 0) then
    new_best := prev_best is not null;
    insert into public.personal_records (user_id, record, value, session_id, achieved_at)
    values (uid, 'best_set', v_best_set, sid, ended)
    on conflict (user_id, record) do update set value = excluded.value, session_id = excluded.session_id,
      achieved_at = excluded.achieved_at;
  end if;

  perform app.settle_wake_days(uid, received);
  if v_verified then xp_gain := xp_gain + v_reps; end if;   -- 1 XP per verified rep
  progress := app.award_progress(uid, sid, xp_gain);
  st := app.streak_json(uid);
  v_result := jsonb_build_object('sessionId', sid, 'verified', v_verified, 'late', late_h > 48, 'repsCounted', v_reps,
    'avgQuality', avg_q, 'wake', wake_result, 'streak', st, 'progress', progress, 'newBestSet', new_best,
    'totals', jsonb_build_object(
      'repsToday', (select reps_total from public.user_stats_local_daily where user_id = uid and local_date = local_d),
      'repsAllTime', (select reps_total from public.user_stats_alltime where user_id = uid)));
  update public.rep_sessions set result = v_result where id = sid;
  return v_result;
end $$;


-- ---------------------------------------------------------------------------
-- Stats dashboard (doc 10 §2): one call per period. Personal = the user's local days.
-- ---------------------------------------------------------------------------
create or replace function public.get_stats(period text) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := auth.uid();
  tz text;
  today date;
  days int;
  d_from date;
  p_from date;
  p_to date;
  first_day date;
  xp bigint;
begin
  if uid is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  if period not in ('week', 'month', 'year', 'all') then raise exception 'invalid period' using errcode = '22023'; end if;
  select coalesce(timezone, 'UTC'), profiles.xp into tz, xp from public.profiles where id = uid;
  today := (now() at time zone tz)::date;
  select min(local_date) into first_day from public.user_stats_local_daily where user_id = uid;
  days := case period when 'week' then 7 when 'month' then 30 when 'year' then 365
                      else greatest(today - coalesce(first_day, today) + 1, 1) end;
  d_from := today - days + 1;
  p_to := d_from - 1;
  p_from := p_to - days + 1;
  return jsonb_build_object(
    'period', period, 'from', d_from, 'to', today,
    'kpis', jsonb_build_object(
      'reps', (select coalesce(sum(reps_total), 0) from public.user_stats_local_daily
                where user_id = uid and local_date between d_from and today),
      'repsPrev', (select coalesce(sum(reps_total), 0) from public.user_stats_local_daily
                    where user_id = uid and local_date between p_from and p_to),
      'bestSet', (select coalesce(max(best_set), 0) from public.user_stats_local_daily
                   where user_id = uid and local_date between d_from and today),
      'bestSetPrev', (select coalesce(max(best_set), 0) from public.user_stats_local_daily
                       where user_id = uid and local_date between p_from and p_to),
      'wakeSuccessPct', (select case when count(*) = 0 then null
                                     else round(100.0 * count(*) filter (where status = 'succeeded') / count(*)) end
                           from public.wake_attempts where user_id = uid and local_date between d_from and today
                            and status in ('succeeded', 'failed', 'missed')),
      'wakeSuccessPctPrev', (select case when count(*) = 0 then null
                                         else round(100.0 * count(*) filter (where status = 'succeeded') / count(*)) end
                               from public.wake_attempts where user_id = uid and local_date between p_from and p_to
                                and status in ('succeeded', 'failed', 'missed')),
      'avgQuality', (select round(sum(avg_quality * reps_total)::numeric / nullif(sum(reps_total), 0))
                       from public.user_stats_local_daily where user_id = uid and local_date between d_from and today
                        and avg_quality is not null),
      'avgQualityPrev', (select round(sum(avg_quality * reps_total)::numeric / nullif(sum(reps_total), 0))
                           from public.user_stats_local_daily where user_id = uid and local_date between p_from and p_to
                            and avg_quality is not null)),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('date', local_date, 'wake', reps_wake, 'battle', reps_battle,
                         'training', reps_training, 'total', reps_total, 'bestSet', best_set, 'avgQuality', avg_quality)
                         order by local_date)
                         from public.user_stats_local_daily where user_id = uid and local_date between d_from and today), '[]'),
    'cumulativeBefore', (select coalesce(sum(reps_total), 0) from public.user_stats_local_daily
                          where user_id = uid and local_date < d_from),
    'wakes', coalesce((select jsonb_agg(jsonb_build_object('date', a.local_date, 'status', a.status,
                         'scheduledAt', app.utc_iso(a.scheduled_at), 'completedAt', app.utc_iso(s.ended_at),
                         'scheduledMinute', extract(hour from a.scheduled_at at time zone tz) * 60
                                            + extract(minute from a.scheduled_at at time zone tz),
                         'completedMinute', case when s.ended_at is null then null else
                                            extract(hour from s.ended_at at time zone tz) * 60
                                            + extract(minute from s.ended_at at time zone tz) end)
                         order by a.local_date)
                         from public.wake_attempts a left join public.rep_sessions s on s.id = a.session_id
                        where a.user_id = uid and a.local_date between d_from and today
                          and a.status in ('succeeded', 'failed', 'missed')), '[]'),
    'heatmap', coalesce((select jsonb_agg(jsonb_build_object('date', local_date, 'reps', reps_total) order by local_date)
                           from public.user_stats_local_daily where user_id = uid and local_date > today - 371), '[]'),
    'records', jsonb_build_object(
      'bestSet', coalesce((select value from public.personal_records where user_id = uid and record = 'best_set'), 0),
      'maxDay', (select coalesce(max(reps_total), 0) from public.user_stats_local_daily where user_id = uid),
      'bestStreak', coalesce((select best from public.streaks where user_id = uid), 0),
      'repsAllTime', (select coalesce(sum(reps_total), 0) from public.user_stats_local_daily where user_id = uid)),
    'progress', app.level_progress(coalesce(xp, 0)) || jsonb_build_object('xp', coalesce(xp, 0)),
    'achievements', jsonb_build_object(
      'unlocked', (select count(*) from public.user_achievements where user_id = uid),
      'total', (select count(*) from public.achievement_definitions where active)));
end $$;
revoke all on function public.get_stats(text) from public, anon;
grant execute on function public.get_stats(text) to authenticated;

-- Achievements screen: every definition with the caller's unlock time (null = locked).
create or replace function public.get_achievements() returns jsonb
language sql stable security definer set search_path = public, app as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'group', d.group_name, 'title', d.title,
    'description', d.description, 'icon', d.icon, 'tier', d.tier, 'xp', d.xp, 'unlockedAt', app.utc_iso(u.unlocked_at))
    order by d.sort), '[]')
  from public.achievement_definitions d
  left join public.user_achievements u on u.achievement_id = d.id and u.user_id = auth.uid()
  where d.active
$$;
revoke all on function public.get_achievements() from public, anon;
grant execute on function public.get_achievements() to authenticated;

grant execute on all functions in schema app to service_role;
