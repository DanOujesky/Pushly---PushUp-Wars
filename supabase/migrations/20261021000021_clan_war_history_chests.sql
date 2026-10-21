-- Clan war history + War Chests (doc 09 §3–4, D-057).
--  * Finishing a war (app.clan_war_finalize writes result->'chests') grants one chest per qualifying roster member.
--  * Chests are earned, never bought, and their content is fixed and shown up front (no randomness): gold 250 XP,
--    silver 150 XP, bronze 100 XP; the medal counts show on the clan page. Cosmetic frames come with the shop later.
create table public.user_chests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source text not null default 'clan_war' check (source in ('clan_war')),
  war_id uuid references public.clan_wars(id) on delete set null,
  clan_name text,
  week_start date,
  tier text not null check (tier in ('bronze', 'silver', 'gold')),
  xp int not null check (xp >= 0),
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  unique (user_id, war_id)
);
create index user_chests_user_idx on public.user_chests(user_id, created_at desc);
alter table public.user_chests enable row level security;
revoke insert, update, delete, truncate on public.user_chests from anon, authenticated;
revoke all on public.user_chests from anon;
create policy user_chests_own on public.user_chests for select to authenticated using (user_id = auth.uid());

create or replace function app.chest_xp(tier text) returns int
language sql immutable as $$ select case tier when 'gold' then 250 when 'silver' then 150 else 100 end $$;

create or replace function app.on_war_finished_chests() returns trigger
language plpgsql security definer set search_path = public, app as $$
begin
  if new.status <> 'finished' or old.status = 'finished' then return new; end if;
  insert into public.user_chests (user_id, war_id, clan_name, week_start, tier, xp)
  select (c->>'userId')::uuid, new.id, cl.name, new.week_start, c->>'tier', app.chest_xp(c->>'tier')
    from jsonb_array_elements(coalesce(new.result->'chests', '[]')) c
    join public.profiles p on p.id = (c->>'userId')::uuid
    left join public.clan_war_rosters ro on ro.war_id = new.id and ro.user_id = p.id
    left join public.clans cl on cl.id = ro.clan_id
  on conflict (user_id, war_id) do nothing;
  return new;
end $$;
create trigger clan_wars_chests after update of status on public.clan_wars
  for each row execute function app.on_war_finished_chests();

-- My chests: unopened first, plus medal counts (all chests ever earned).
create or replace function public.get_war_chests() returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object(
    'unopened', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'tier', c.tier, 'xp', c.xp,
                                   'clanName', c.clan_name, 'weekStart', c.week_start) order by c.created_at)
                            from public.user_chests c where c.user_id = app.require_user() and c.opened_at is null), '[]'),
    'medals', jsonb_build_object(
      'gold', (select count(*) from public.user_chests c where c.user_id = app.require_user() and c.tier = 'gold'),
      'silver', (select count(*) from public.user_chests c where c.user_id = app.require_user() and c.tier = 'silver'),
      'bronze', (select count(*) from public.user_chests c where c.user_id = app.require_user() and c.tier = 'bronze')))
$$;
revoke all on function public.get_war_chests() from public, anon;
grant execute on function public.get_war_chests() to authenticated;

-- Opens a chest once: adds its XP (level recomputed). Returns {tier, xp} + level progress.
create or replace function public.open_chest(chest_id uuid) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  c public.user_chests;
  v_xp bigint;
begin
  update public.user_chests x set opened_at = now()
   where x.id = chest_id and x.user_id = me and x.opened_at is null
  returning * into c;
  if not found then
    raise exception 'chest not found or already opened' using errcode = 'P0002';
  end if;
  update public.profiles set xp = xp + c.xp where id = me returning xp into v_xp;
  update public.profiles set level = app.level_for_xp(v_xp) where id = me;
  return jsonb_build_object('tier', c.tier, 'xp', c.xp, 'totalXp', v_xp) || app.level_progress(v_xp);
end $$;
revoke all on function public.open_chest(uuid) from public, anon;
grant execute on function public.open_chest(uuid) to authenticated;

-- Finished wars of a clan, newest first (doc 09 §4 "war history (W/L streak)"). Members and outsiders alike:
-- results are public like the clan leaderboard.
create or replace function public.get_clan_war_history(clan_id uuid default null, lim int default 20) returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_cid uuid := coalesce(clan_id, app.my_clan_id(me));
begin
  if v_cid is null then return '[]'; end if;
  return coalesce((select jsonb_agg(x.j order by x.week desc) from (
    select w.week_start week, jsonb_build_object('id', w.id, 'weekStart', w.week_start,
      'opponent', case when o.id is null then null
                       else jsonb_build_object('id', o.id, 'name', o.name, 'tag', o.tag, 'badge', o.badge) end,
      'us', case when w.clan_a = v_cid then w.score_a else w.score_b end,
      'them', case when w.clan_a = v_cid then w.score_b else w.score_a end,
      'won', w.winner = v_cid, 'draw', w.winner is null, 'reason', w.result->>'reason') j
      from public.clan_wars w
      left join public.clans o on o.id = case when w.clan_a = v_cid then w.clan_b else w.clan_a end
     where v_cid in (w.clan_a, w.clan_b) and w.status = 'finished'
     order by w.week_start desc limit greatest(1, least(coalesce(lim, 20), 52))) x), '[]');
end $$;
revoke all on function public.get_clan_war_history(uuid, int) from public, anon;
grant execute on function public.get_clan_war_history(uuid, int) to authenticated;
