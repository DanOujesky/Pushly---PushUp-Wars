-- 0030 — Pro cosmetics (D-074, doc 13 §2): profile frames and extra clan emblems. Cosmetic only — nothing here touches
-- reps, trophies, matchmaking, wars or leaderboards. Catalog: shared/cosmetics/cosmetics.json.
--
-- * profiles.frame: a Pro frame around the avatar. Shown on user cards only while the user is Pro (when Pro ends the
--   frame simply stops showing; it comes back if they subscribe again).
-- * clans.badge = {shape, color, emblem}. Pro emblems can only be picked by a Pro leader / co-leader; a badge that was
--   set while Pro stays (the clan shouldn't lose its look because one member's subscription ended).

alter table public.profiles add column frame text check (frame in ('gold', 'neon', 'fire', 'ice', 'royal'));

create or replace function app.user_card(uid uuid, viewer uuid) returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'avatarPreset', p.avatar_preset,
    'country', p.country, 'level', p.level, 'trophies', p.trophies, 'pro', p.is_pro,
    'frame', case when p.is_pro then p.frame end,
    'clanTag', (select c.tag::text from public.clan_members m join public.clans c on c.id = m.clan_id where m.user_id = p.id),
    'streak', case when p.profile_visibility = 'public' or p.id = viewer
                     or (p.profile_visibility = 'friends' and app.are_friends(p.id, viewer))
                   then coalesce((select current from public.streaks s where s.user_id = p.id), 0) end)
  from public.profiles p where p.id = uid
$$;

-- Pick a frame (null = none). Pro only; returns my user card.
create or replace function public.set_profile_frame(frame text) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  if set_profile_frame.frame is not null then
    if set_profile_frame.frame not in ('gold', 'neon', 'fire', 'ice', 'royal') then
      raise exception 'unknown frame' using errcode = '22023', hint = 'invalid_frame';
    end if;
    if not (select is_pro from public.profiles where id = me) then
      raise exception 'Pushly Pro needed' using errcode = '42501', hint = 'pro_required';
    end if;
  end if;
  update public.profiles set frame = set_profile_frame.frame where id = me;
  return app.user_card(me, me);
end $$;

revoke all on function public.set_profile_frame(text) from public, anon;
grant execute on function public.set_profile_frame(text) to authenticated;

-- Badge shape check + Pro emblems (only when the badge changes, only for a signed-in actor).
create or replace function app.check_clan_badge() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  b jsonb := coalesce(new.badge, '{}');
  k text;
  v_changed boolean;
  v_actor uuid;
begin
  if tg_op = 'UPDATE' and new.badge is not distinct from old.badge then return new; end if;
  if jsonb_typeof(b) <> 'object' then
    raise exception 'invalid badge' using errcode = '22023', hint = 'invalid_badge';
  end if;
  for k in select jsonb_object_keys(b) loop
    if k not in ('shape', 'color', 'emblem') then
      raise exception 'invalid badge' using errcode = '22023', hint = 'invalid_badge';
    end if;
  end loop;
  if (b ? 'shape' and b->>'shape' not in ('shield', 'round', 'hex'))
     or (b ? 'color' and b->>'color' not in ('flame', 'volt', 'cyan', 'lime', 'gold', 'red', 'diamond', 'pink'))
     or (b ? 'emblem' and b->>'emblem' not in ('flame', 'fist', 'bolt', 'muscle', 'wolf', 'lion', 'eagle', 'skull',
                                               'dragon', 'crown', 'diamond', 'rocket', 'trident', 'shark', 'comet', 'volcano')) then
    raise exception 'invalid badge' using errcode = '22023', hint = 'invalid_badge';
  end if;
  if coalesce(b->>'emblem', '') in ('dragon', 'crown', 'diamond', 'rocket', 'trident', 'shark', 'comet', 'volcano') then
    if tg_op = 'INSERT' then
      v_changed := true;
    else
      v_changed := (old.badge->>'emblem') is distinct from (b->>'emblem');
    end if;
    if v_changed then
      v_actor := auth.uid();
      if v_actor is not null and not coalesce((select is_pro from public.profiles where id = v_actor), false) then
        raise exception 'Pushly Pro needed for this emblem' using errcode = '42501', hint = 'pro_required';
      end if;
    end if;
  end if;
  new.badge := b;
  return new;
end $$;

create trigger clans_badge_check before insert or update of badge on public.clans
  for each row execute function app.check_clan_badge();
