-- 0008 — get_wake_summary also returns today's push-ups (PS-15). 0007 is applied on the hosted project, so the
-- change is a new migration (never edit applied ones).
create or replace function public.get_wake_summary() returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := auth.uid();
  tz text;
  today date;
begin
  if uid is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  perform app.settle_wake_days(uid, now());
  select coalesce(timezone, 'UTC') into tz from public.profiles where id = uid;
  today := (now() at time zone tz)::date;
  return jsonb_build_object(
    'today', today,
    'plan', app.day_plan(uid, today, tz),
    'streak', app.streak_json(uid),
    'repsToday', coalesce((select reps_total from public.user_stats_local_daily
                            where user_id = uid and local_date = today), 0),
    'attempts', coalesce((select jsonb_agg(app.attempt_json(a) order by a.local_date desc)
                            from (select * from public.wake_attempts where user_id = uid
                                   order by local_date desc limit 14) a), '[]'));
end $$;
revoke all on function public.get_wake_summary() from public, anon;
grant execute on function public.get_wake_summary() to authenticated;
