-- 0035 — Clan War detail (D-079): who did how many push-ups in a war, per clan and per day, so leaders can see who
-- pulls their weight; the war history gains the MVP and the number of fighters.
--
-- * get_clan_war_detail(war_id): the war (as clan-war-state's war object) + every clan's fighters: counted points,
--   raw push-ups, one number per war day (Mon..Sun UTC) and whether they are still in that clan. Members who were in
--   the clan before the war ended but scored nothing are listed with 0 — that is the point for leaders.
-- * get_clan_war_results: + `mvp` (user card) and `contributors` (fighters with ≥ 1 point) of the clan.
-- Read only, security definer like the other war reads; clan war tables stay closed to clients.

create or replace function public.get_clan_war_detail(war_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  g public.clan_war_groups;
  v_mine uuid := app.my_clan_id(me);
  v_view uuid;
  v_days date[];
begin
  select * into g from public.clan_war_groups where id = war_id;
  if not found then raise exception 'war not found' using errcode = 'P0002'; end if;
  select e.clan_id into v_view from public.clan_war_entries e where e.group_id = war_id and e.clan_id = v_mine;
  if v_view is null then
    select e.clan_id into v_view from public.clan_war_entries e where e.group_id = war_id order by e.joined_at, e.clan_id limit 1;
  end if;
  v_days := array(select (g.week_start + i)::date from generate_series(0, 6) i);
  return jsonb_build_object(
    'war', app.clan_war_group_json(war_id, v_view, me),
    'days', to_jsonb(v_days),
    'clans', (select coalesce(jsonb_agg(jsonb_build_object(
        'clanId', e.clan_id,
        'isMine', e.clan_id = v_view,
        'fighters', (select coalesce(jsonb_agg(jsonb_build_object(
              'user', app.user_card(x.uid, me),
              'points', x.points,
              'raw', x.raw,
              'days', (select jsonb_agg(coalesce((select q.counted_reps from public.clan_war_points q
                                                   where q.group_id = war_id and q.user_id = x.uid and q.day = d), 0) order by d)
                         from unnest(v_days) d),
              'inClan', exists (select 1 from public.clan_members m where m.user_id = x.uid and m.clan_id = e.clan_id))
              order by x.points desc, x.raw desc, lower(pr.username)), '[]')
            from (select ids.uid, coalesce(sum(p.counted_reps), 0)::int points, coalesce(sum(p.raw_reps), 0)::int raw
                    from (select q.user_id uid from public.clan_war_points q where q.group_id = war_id and q.clan_id = e.clan_id
                          union
                          select m.user_id from public.clan_members m
                           where m.clan_id = e.clan_id and m.joined_at < app.war_ends_at(g.week_start)) ids
                    left join public.clan_war_points p on p.group_id = war_id and p.clan_id = e.clan_id and p.user_id = ids.uid
                   group by ids.uid) x
            join public.profiles pr on pr.id = x.uid))
        order by coalesce(e.rank, 99), e.score desc, e.joined_at), '[]')
      from public.clan_war_entries e where e.group_id = war_id));
end $$;

create or replace function public.get_clan_war_results(clan_id uuid default null, lim int default 20) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := coalesce(clan_id, app.my_clan_id(me));
begin
  if v_cid is null then return '[]'; end if;
  return coalesce((select jsonb_agg(x.j order by x.fin desc) from (
    select g.finished_at fin, jsonb_build_object('id', g.id, 'weekStart', g.week_start, 'rank', e.rank,
      'of', (select count(*) from public.clan_war_entries o where o.group_id = g.id), 'score', e.score,
      'ratingDelta', e.rating_delta,
      'contributors', (select count(*) from (select p.user_id from public.clan_war_points p
                         where p.group_id = g.id and p.clan_id = v_cid group by p.user_id having sum(p.counted_reps) > 0) c),
      'mvp', case when e.mvp is not null then app.user_card(e.mvp, me) end,
      'clans', (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'badge', c.badge,
                                                    'score', o.score, 'rank', o.rank, 'isMine', o.clan_id = v_cid) order by o.rank, o.score desc)
                  from public.clan_war_entries o join public.clans c on c.id = o.clan_id where o.group_id = g.id)) j
      from public.clan_war_entries e join public.clan_war_groups g on g.id = e.group_id
     where e.clan_id = v_cid and g.status = 'finished'
     order by g.finished_at desc limit greatest(1, least(coalesce(lim, 20), 52))) x), '[]');
end $$;

revoke all on function public.get_clan_war_detail(uuid) from public, anon;
grant execute on function public.get_clan_war_detail(uuid) to authenticated;
