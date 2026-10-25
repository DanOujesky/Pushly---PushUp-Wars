-- 0029 — Pushly Pro perks (D-073): unlimited ghost battles for Pro (ghosts never change trophies, so it's comfort, not
-- pay-to-win — doc 13 §2) and the PRO badge: every user card carries `pro` so leaderboards, clans and friend lists
-- can show it.

create or replace function app.user_card(uid uuid, viewer uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'avatarPreset', p.avatar_preset,
    'country', p.country, 'level', p.level, 'trophies', p.trophies, 'pro', p.is_pro,
    'clanTag', (select c.tag::text from public.clan_members m join public.clans c on c.id = m.clan_id where m.user_id = p.id),
    'streak', case when p.profile_visibility = 'public' or p.id = viewer
                     or (p.profile_visibility = 'friends' and app.are_friends(p.id, viewer))
                   then coalesce((select current from public.streaks s where s.user_id = p.id), 0) end)
  from public.profiles p where p.id = uid
$$;

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
  if v_today >= 3 and not p.is_pro then
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
