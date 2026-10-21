-- Friend / player profile (doc 15 §1, P6-02): what another user may see about someone. Visibility follows
-- profiles.profile_visibility (public / friends / private); blocked pairs and unfinished profiles look like "not found".
create or replace function public.get_user_profile(user_id uuid default null, username text default null) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  p public.profiles;
  v_rel text;
  f public.friendships;
  v_visible boolean;
begin
  if user_id is not null then
    select * into p from public.profiles x where x.id = get_user_profile.user_id;
  elsif username is not null then
    select * into p from public.profiles x where x.username = get_user_profile.username::citext;
  end if;
  if p.id is null or not p.onboarding_completed or (p.id <> me and app.is_blocked(me, p.id)) then
    return null;
  end if;
  if p.id = me then
    v_rel := 'self';
  else
    select * into f from public.friendships x where x.user_a = least(me, p.id) and x.user_b = greatest(me, p.id);
    v_rel := case when f.status is null then 'none'
                  when f.status::text = 'accepted' then 'friends'
                  when f.status::text = 'pending' and f.requested_by = me then 'outgoing'
                  when f.status::text = 'pending' then 'incoming'
                  else 'none' end;
  end if;
  v_visible := p.id = me or p.profile_visibility = 'public' or (p.profile_visibility = 'friends' and v_rel = 'friends');
  return jsonb_build_object(
    'user', app.user_card(p.id, me),
    'relation', v_rel,
    'visible', v_visible,
    'league', app.league_for(greatest(p.trophies, 0)),
    'stats', case when v_visible then jsonb_build_object(
        'repsTotal', coalesce((select a.reps_total from public.user_stats_alltime a where a.user_id = p.id), 0),
        'bestSet', coalesce((select a.best_set from public.user_stats_alltime a where a.user_id = p.id), 0),
        'bestStreak', coalesce((select s.best from public.streaks s where s.user_id = p.id), 0),
        'achievements', (select count(*) from public.user_achievements u where u.user_id = p.id),
        'bestTrophies', p.best_trophies,
        'memberSince', to_char(p.created_at at time zone 'UTC', 'YYYY-MM')) end,
    'headToHead', case when p.id = me then null else (
        select jsonb_build_object(
          'wins', count(*) filter (where b.result->>'winner' = case when b.player_a = me then 'a' else 'b' end),
          'losses', count(*) filter (where b.result->>'winner' = case when b.player_a = me then 'b' else 'a' end),
          'draws', count(*) filter (where b.result->>'winner' is null))
        from public.battles b
       where b.status = 'settled' and ((b.player_a = me and b.player_b = p.id) or (b.player_a = p.id and b.player_b = me))) end);
end $$;
revoke all on function public.get_user_profile(uuid, text) from public, anon;
grant execute on function public.get_user_profile(uuid, text) to authenticated;
