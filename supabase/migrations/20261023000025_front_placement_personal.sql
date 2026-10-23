-- 0025 — FRONT placement is personal only (D-064). From the front the camera can't see the knees, so knee push-ups
-- can't be ruled out: front sessions count for the wake challenge, streaks, XP and personal stats, but not for
-- leaderboards, clan wars (user_stats_daily / weekly / monthly) or battles. The rep log carries `placement`.

alter table public.rep_sessions add column placement text not null default 'side' check (placement in ('side', 'front'));

-- apply_validated_session (0010) + placement: stored, and front sessions are not competitive.
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
  v_front boolean := coalesce(s->>'placement', 'side') = 'front';
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
    late, received_at, placement)
  values (sid, uid, (p->>'deviceId')::uuid, ctx::public.session_context, s->>'occurrenceId', started, ended, v_reps,
    v_best_set, avg_q, coalesce(s->'rejected', '{}'), (s->>'specVersion')::smallint, s->>'appVersion',
    (s->>'platform')::public.platform_t, v_verified, v_verification, late_h > 48, received,
    case when v_front then 'front' else 'side' end);
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
          perform app.bump_stats(uid, (plan->>'t0')::timestamptz, null, null, 0, 0, null, v_points, not v_front);
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

  perform app.bump_stats(uid, started, local_d, ctx, v_reps, v_best_set, avg_q, 0,
                         v_verified and late_h <= 48 and not v_front);
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
    'avgQuality', avg_q, 'competitive', v_verified and late_h <= 48 and not v_front, 'wake', wake_result, 'streak', st, 'progress', progress, 'newBestSet', new_best,
    'totals', jsonb_build_object(
      'repsToday', (select reps_total from public.user_stats_local_daily where user_id = uid and local_date = local_d),
      'repsAllTime', (select reps_total from public.user_stats_alltime where user_id = uid)));
  update public.rep_sessions set result = v_result where id = sid;
  return v_result;
end $$;

-- battle_reps (0018) + front sessions give no battle reps (flag front_placement).
create or replace function app.battle_reps(v public.battles, uid uuid, out reps jsonb, out flag text)
language plpgsql stable security definer set search_path = public, app as $$
declare
  v_cap int;
  v_any boolean;
  v_front boolean;
begin
  if uid is null and v.ghost_run_id is not null then
    select g.timeline into reps from public.ghost_runs g where g.id = v.ghost_run_id;
    reps := coalesce(reps, '[]');
    flag := null;
    return;
  end if;
  select bool_or(true), sum(case when s.verified and s.placement is distinct from 'front' then s.reps_counted else 0 end),
         bool_and(s.verified), bool_or(s.placement = 'front')
    into v_any, v_cap, flag, v_front
    from public.rep_sessions s where s.battle_id = v.id and s.user_id = uid;
  if v_any is null then
    v_cap := null;
    flag := 'missing_log';
  elsif v_front then
    flag := 'front_placement';         -- battles need the side view (knees visible), D-064
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

grant execute on all functions in schema app to service_role;
