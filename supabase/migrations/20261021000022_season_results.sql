-- Season results (doc 08 §2.5, P7-09): at the monthly rollover every player who battled in the closing season gets an
-- archived result — final and best trophies, the best league reached (the season badge) and the final rank. Rewards
-- are cosmetic: the badge shows on the Battle tab; frames/emotes come with the cosmetics shop (D-057).
create table public.season_results (
  season_id smallint not null references public.seasons(id),
  user_id uuid not null references public.profiles(id) on delete cascade,
  final_trophies int not null,
  best_trophies int not null,
  league text not null,
  tier text,
  rank int not null,
  created_at timestamptz not null default now(),
  primary key (season_id, user_id)
);
create index season_results_user_idx on public.season_results(user_id, season_id desc);
alter table public.season_results enable row level security;
revoke insert, update, delete, truncate on public.season_results from anon, authenticated;
revoke all on public.season_results from anon;
create policy season_results_own on public.season_results for select to authenticated using (user_id = auth.uid());

create or replace function app.archive_season(sid smallint) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_n int;
begin
  insert into public.season_results (season_id, user_id, final_trophies, best_trophies, league, tier, rank)
  select sid, x.user_id, x.final, x.best, app.league_for(x.best)->>'league', app.league_for(x.best)->>'tier',
         rank() over (order by x.final desc)
    from (select l.user_id, max(l.balance_after) best, p.trophies final
            from public.trophy_ledger l join public.profiles p on p.id = l.user_id
           where l.season_id = sid and l.reason in ('battle_win', 'battle_loss', 'battle_draw', 'reversal')
           group by l.user_id, p.trophies) x
  on conflict (season_id, user_id) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function app.rollover_season(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_new smallint := app.current_season(now_at);
  v_old smallint;
  v_n int;
begin
  if not exists (select 1 from public.seasons where status = 'active' and id <> v_new) then return 0; end if;
  -- Archive before the soft reset (final trophies = the closing balance).
  for v_old in select id from public.seasons where status = 'active' and id <> v_new loop
    perform app.archive_season(v_old);
  end loop;
  update public.seasons set status = 'closed' where status = 'active' and id <> v_new;
  insert into public.trophy_ledger (user_id, delta, balance_after, reason, season_id)
  select id, app.season_reset(trophies) - trophies, app.season_reset(trophies), 'season_reset', v_new
    from public.profiles where trophies > 2000;
  get diagnostics v_n = row_count;
  update public.profiles set trophies = app.season_reset(trophies), trophy_floor = 0 where trophies > 0 or trophy_floor > 0;
  return v_n;
end $$;

-- My past seasons, newest first: [{seasonId, month "YYYY-MM", finalTrophies, bestTrophies, league, tier, rank}].
create or replace function public.get_season_history() returns jsonb
language sql stable security definer set search_path = public, app as $$
  select coalesce(jsonb_agg(jsonb_build_object('seasonId', r.season_id,
           'month', to_char(s.starts_at at time zone 'UTC', 'YYYY-MM'),
           'finalTrophies', r.final_trophies, 'bestTrophies', r.best_trophies,
           'league', r.league, 'tier', r.tier, 'rank', r.rank) order by r.season_id desc), '[]')
    from public.season_results r join public.seasons s on s.id = r.season_id
   where r.user_id = app.require_user()
$$;
revoke all on function public.get_season_history() from public, anon;
grant execute on function public.get_season_history() to authenticated;
