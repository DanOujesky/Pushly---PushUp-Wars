-- 0027 — Clan Wars with more fight (D-068): a live war feed (who just scored for which side), lead-change alerts in
-- the clan chat, day-by-day results, the opponent's top fighters, and a "rally" — any member can call the whole clan
-- to arms (push + chat), once per clan every 6 hours.

alter table public.clans add column last_rally_at timestamptz;

create table public.clan_war_feed (
  id bigint generated always as identity primary key,
  war_id uuid not null references public.clan_wars(id) on delete cascade,
  clan_id uuid not null,
  user_id uuid references public.profiles(id) on delete cascade,
  points int not null check (points > 0),
  created_at timestamptz not null default now()
);
create index clan_war_feed_war_idx on public.clan_war_feed(war_id, created_at desc);
alter table public.clan_war_feed enable row level security;
revoke all on public.clan_war_feed from anon, authenticated;     -- read through get_clan_war only

-- on_stats_daily_war (0015) + feed rows for every gain and a chat line when the lead changes (max 1 per war per hour).
create or replace function app.on_stats_daily_war() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  r record;
  v_trust int;
  v_counted int;
  v_before int;
  v_total bigint;
  vw public.clan_wars;
  v_old int;
  v_new int;
  v_leader uuid;
  v_trailer uuid;
begin
  select trust_score into v_trust from public.profiles where id = new.user_id;
  for r in select ro.war_id, ro.clan_id, w.clan_a, w.clan_b from public.clan_war_rosters ro join public.clan_wars w on w.id = ro.war_id
            where ro.user_id = new.user_id and ro.left_at is null and w.status = 'live' and w.week_start = app.war_week_start(new.day::timestamp at time zone 'UTC')
  loop
    v_counted := case when v_trust < 30 then 0 else app.clan_war_day_total(new.reps_total, v_trust < 50) end;
    select coalesce((select counted_reps from public.clan_war_member_daily d
                      where d.war_id = r.war_id and d.user_id = new.user_id and d.day = new.day), 0) into v_before;
    insert into public.clan_war_member_daily as d (war_id, user_id, day, raw_reps, counted_reps)
    values (r.war_id, new.user_id, new.day, new.reps_total, v_counted)
    on conflict (war_id, user_id, day) do update set raw_reps = excluded.raw_reps, counted_reps = excluded.counted_reps;
    if v_counted > v_before then
      insert into public.clan_war_feed (war_id, clan_id, user_id, points) values (r.war_id, r.clan_id, new.user_id, v_counted - v_before);
    end if;
    select coalesce(sum(d.counted_reps), 0) into v_total from public.clan_war_member_daily d
      join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
     where d.war_id = r.war_id and ro.clan_id = r.clan_id;
    select * into vw from public.clan_wars where id = r.war_id;
    v_old := sign(vw.score_a - vw.score_b)::int;
    if r.clan_id = r.clan_a then
      update public.clan_wars set score_a = v_total, score_a_at = case when score_a <> v_total then now() else score_a_at end
       where id = r.war_id returning * into vw;
    else
      update public.clan_wars set score_b = v_total, score_b_at = case when score_b <> v_total then now() else score_b_at end
       where id = r.war_id returning * into vw;
    end if;
    v_new := sign(vw.score_a - vw.score_b)::int;
    if vw.clan_b is not null and v_new <> 0 and v_new <> v_old
       and not exists (select 1 from public.clan_events e where e.type = 'war_lead' and e.payload->>'warId' = vw.id::text
                         and e.created_at > now() - interval '1 hour') then
      v_leader := case when v_new > 0 then vw.clan_a else vw.clan_b end;
      v_trailer := case when v_new > 0 then vw.clan_b else vw.clan_a end;
      insert into public.clan_events (clan_id, actor, type, payload)
      values (v_leader, new.user_id, 'war_lead', jsonb_build_object('warId', vw.id));
      perform app.clan_system_message(v_leader, '⚔️ We took the lead in the Clan War!',
                                      jsonb_build_object('event', 'war_lead', 'warId', vw.id));
      perform app.clan_system_message(v_trailer,
        '⚠️ [' || (select tag from public.clans where id = v_leader) || '] overtook us in the Clan War — time to push!',
        jsonb_build_object('event', 'war_lost_lead', 'warId', vw.id));
    end if;
  end loop;
  return new;
end $$;

-- get_clan_war (0015) + days, theirTop, feed, rally.
create or replace function public.get_clan_war(clan_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := coalesce(clan_id, app.my_clan_id(me));
  w public.clan_wars;
  v_mine boolean;
  v_them uuid;
  v_today int;
  v_rally timestamptz;
begin
  if v_cid is null then return null; end if;
  select * into w from public.clan_wars x where v_cid in (x.clan_a, x.clan_b) order by x.week_start desc limit 1;
  if not found then return null; end if;
  v_mine := v_cid = w.clan_a;
  v_them := case when v_mine then w.clan_b else w.clan_a end;
  select coalesce(sum(d.raw_reps), 0) into v_today from public.clan_war_member_daily d
   where d.war_id = w.id and d.user_id = me and d.day = (now() at time zone 'UTC')::date;
  select last_rally_at into v_rally from public.clans where id = v_cid;
  return jsonb_build_object('id', w.id, 'status', w.status, 'weekStart', w.week_start,
    'endsAt', app.utc_iso((w.week_start + 7)::timestamp at time zone 'UTC'),
    'opponent', case when v_them is null then null else app.clan_json(v_them, me) end,
    'score', jsonb_build_object('us', case when v_mine then w.score_a else w.score_b end,
                                'them', case when v_mine then w.score_b else w.score_a end),
    'result', case when w.status = 'finished' then w.result || jsonb_build_object('won', w.winner = v_cid, 'draw', w.winner is null) end,
    'myToday', jsonb_build_object('raw', v_today, 'counted', app.clan_war_day_total(v_today, false), 'fullCap', 200, 'halfCap', 400),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(s.user_id, me), 'reps', s.t) order by s.t desc), '[]')
              from (select d.user_id, sum(d.counted_reps) t from public.clan_war_member_daily d
                      join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
                     where d.war_id = w.id and ro.clan_id = v_cid group by 1 order by 2 desc limit 5) s),
    'theirTop', (select coalesce(jsonb_agg(jsonb_build_object('user', app.user_card(s.user_id, me), 'reps', s.t) order by s.t desc), '[]')
                   from (select d.user_id, sum(d.counted_reps) t from public.clan_war_member_daily d
                           join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
                          where d.war_id = w.id and ro.clan_id = v_them group by 1 order by 2 desc limit 3) s),
    'days', (select jsonb_agg(jsonb_build_object('day', dd::date,
               'us', coalesce((select sum(d.counted_reps) from public.clan_war_member_daily d
                                join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
                               where d.war_id = w.id and ro.clan_id = v_cid and d.day = dd::date), 0),
               'them', coalesce((select sum(d.counted_reps) from public.clan_war_member_daily d
                                  join public.clan_war_rosters ro on ro.war_id = d.war_id and ro.user_id = d.user_id
                                 where d.war_id = w.id and ro.clan_id = v_them and d.day = dd::date), 0)) order by dd)
               from generate_series(w.week_start::timestamp, w.week_start::timestamp + interval '6 days', interval '1 day') dd),
    'feed', (select coalesce(jsonb_agg(jsonb_build_object('side', case when f.clan_id = v_cid then 'us' else 'them' end,
                                                          'username', coalesce(p.username, 'Deleted user'), 'points', f.points,
                                                          'at', app.utc_iso(f.created_at)) order by f.created_at desc, f.id desc), '[]')
               from (select * from public.clan_war_feed x where x.war_id = w.id order by x.created_at desc, x.id desc limit 15) f
               left join public.profiles p on p.id = f.user_id),
    'rally', jsonb_build_object('available', w.status = 'live' and app.my_clan_id(me) = v_cid
                                              and (v_rally is null or v_rally <= now() - interval '6 hours'),
                                'nextAt', case when v_rally > now() - interval '6 hours' then app.utc_iso(v_rally + interval '6 hours') end));
end $$;

-- Rally (D-068): any member calls the clan to arms — push to every other member + a chat line. Once per clan per 6 h.
create or replace function public.clan_rally() returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := app.my_clan_id(me);
  w public.clan_wars;
  v_gap bigint;
  v_name text;
  m record;
begin
  if v_cid is null then raise exception 'not in a clan' using errcode = 'P0002', hint = 'no_clan'; end if;
  select * into w from public.clan_wars x where v_cid in (x.clan_a, x.clan_b) and x.status = 'live' order by x.week_start desc limit 1;
  if not found then raise exception 'no live war' using errcode = 'P0001', hint = 'no_war'; end if;
  update public.clans set last_rally_at = now()
   where id = v_cid and (last_rally_at is null or last_rally_at <= now() - interval '6 hours');
  if not found then raise exception 'rally cooldown' using errcode = 'P0001', hint = 'rally_cooldown'; end if;
  v_gap := case when v_cid = w.clan_a then w.score_a - w.score_b else w.score_b - w.score_a end;
  select username into v_name from public.profiles where id = me;
  perform app.clan_system_message(v_cid,
    '📣 ' || coalesce(v_name, 'A member') || ' calls everyone to the war! ' ||
    case when w.clan_b is null then 'Every push-up counts.'
         when v_gap < 0 then 'We are ' || (-v_gap) || ' behind.'
         when v_gap > 0 then 'We lead by ' || v_gap || ' — keep it up!'
         else 'It''s tied!' end,
    jsonb_build_object('event', 'rally', 'warId', w.id, 'userId', me));
  for m in select user_id from public.clan_members where clan_id = v_cid and user_id <> me loop
    perform app.enqueue_push(m.user_id, 'clan_rally', 'clan',
      jsonb_build_object('username', v_name, 'gap', v_gap, 'warId', w.id, 'clanId', v_cid), 'rally:' || v_cid);
  end loop;
  return public.get_clan_war(v_cid);
end $$;
revoke all on function public.clan_rally() from public, anon;
grant execute on function public.clan_rally() to authenticated;
grant execute on all functions in schema app to service_role;
