-- 0028 — Friend battles are always friendly (D-071): founder 2026-10-25 — push-ups against a friend never win or lose
-- trophies. `create_battle_invite` keeps its signature (older apps still send `ranked`) but ignores the flag; pending
-- ranked invites are turned friendly so nothing in flight can become a ranked friend battle. Trophies come from
-- Quick match only.

update public.battle_invites set ranked = false where ranked and status = 'pending';

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
  perform app.hit_rate_limit(me, 'battle_invite', 30, interval '1 hour');
  update public.battle_invites set status = 'cancelled'
   where from_user = me and status = 'pending' and battle_invites.to_user is not distinct from create_battle_invite.to_user;
  insert into public.battle_invites (from_user, to_user, code, mode, variant, ranked, expires_at)
  values (me, to_user, substr(md5(random()::text || clock_timestamp()::text), 1, 10), mode::public.battle_mode, v_variant,
          false, now() + interval '5 minutes')
  returning * into v_inv;
  if to_user is not null then
    perform app.enqueue_push(to_user, 'battle_invite', 'battles',
      jsonb_build_object('username', (select username from public.profiles where id = me), 'inviteId', v_inv.id, 'mode', mode),
      'invite:' || me);
  end if;
  return jsonb_build_object('id', v_inv.id, 'code', v_inv.code, 'expiresAt', app.utc_iso(v_inv.expires_at),
                            'mode', v_inv.mode, 'variant', v_inv.variant, 'ranked', v_inv.ranked);
end $$;
