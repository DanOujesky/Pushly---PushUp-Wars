-- 0016 — reports (UGC safety), account deletion + data export (doc 16 §4), Pushly Pro entitlements (doc 13 §2).
-- Roadmap P9-03, P10-01 (server side).

-- ---------------------------------------------------------------------------
-- Reports (doc 16 §5: report & block everywhere a user can see another user)
-- ---------------------------------------------------------------------------
create table public.reports (
  id bigint generated always as identity primary key,
  reporter uuid references public.profiles(id) on delete set null,
  target_user uuid references public.profiles(id) on delete set null,
  battle_id uuid references public.battles(id) on delete set null,
  message_id bigint references public.clan_messages(id) on delete set null,
  clan_id uuid references public.clans(id) on delete set null,
  reason text not null check (reason in ('cheating', 'harassment', 'inappropriate_video', 'inappropriate_name', 'spam', 'other')),
  details text check (char_length(details) <= 1000),
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;

-- target: {"userId": …} | {"battleId": …} | {"messageId": …} | {"clanId": …}
create or replace function public.report(target jsonb, reason text, details text default null) returns bigint
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_id bigint;
  v_user uuid := nullif(target->>'userId', '')::uuid;
  v_battle uuid := nullif(target->>'battleId', '')::uuid;
  v_msg bigint := nullif(target->>'messageId', '')::bigint;
  v_clan uuid := nullif(target->>'clanId', '')::uuid;
begin
  if num_nonnulls(v_user, v_battle, v_msg, v_clan) = 0 then raise exception 'nothing to report' using errcode = '22023'; end if;
  if v_battle is not null and not exists (select 1 from public.battles b where b.id = v_battle and me in (b.player_a, b.player_b)) then
    raise exception 'battle not found' using errcode = 'P0002';
  end if;
  if v_msg is not null then
    select m.user_id into v_user from public.clan_messages m where m.id = v_msg and m.clan_id = app.my_clan_id(me);
    if not found then raise exception 'message not found' using errcode = 'P0002'; end if;
  end if;
  if v_battle is not null and v_user is null then
    select case when b.player_a = me then b.player_b else b.player_a end into v_user from public.battles b where b.id = v_battle;
  end if;
  perform app.hit_rate_limit(me, 'report', 20, interval '1 day');
  insert into public.reports (reporter, target_user, battle_id, message_id, clan_id, reason, details)
  values (me, v_user, v_battle, v_msg, v_clan, reason, left(details, 1000))
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Data export (GDPR, doc 16 §4): everything stored about the caller, as one JSON document.
-- Raw rep logs and feature traces are left out (anti-cheat material, deleted after 90 days).
-- ---------------------------------------------------------------------------
create or replace function public.export_my_data() returns jsonb
language plpgsql stable security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  t jsonb := '{}';
begin
  t := jsonb_build_object(
    'exportedAt', app.utc_iso(now()),
    'profile', (select to_jsonb(p) - 'mmr' - 'mmr_rd' - 'mmr_vol' from public.profiles p where p.id = me),
    'devices', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'platform', d.platform, 'model', d.model,
                  'appVersion', d.app_version, 'createdAt', d.created_at, 'revokedAt', d.revoked_at)), '[]')
                  from public.devices d where d.user_id = me),
    'alarms', (select coalesce(jsonb_agg(a.data), '[]') from public.alarm_schedules a where a.user_id = me),
    'wakeAttempts', (select coalesce(jsonb_agg(to_jsonb(w) - 'user_id' order by w.local_date), '[]') from public.wake_attempts w where w.user_id = me),
    'streak', (select to_jsonb(s) - 'user_id' from public.streaks s where s.user_id = me),
    'sessions', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'context', s.context, 'startedAt', s.started_at,
                   'endedAt', s.ended_at, 'reps', s.reps_counted, 'bestSet', s.best_set, 'avgQuality', s.avg_quality,
                   'verified', s.verified) order by s.started_at), '[]') from public.rep_sessions s where s.user_id = me),
    'dailyStats', (select coalesce(jsonb_agg(to_jsonb(d) - 'user_id' order by d.local_date), '[]') from public.user_stats_local_daily d where d.user_id = me),
    'records', (select coalesce(jsonb_agg(to_jsonb(r) - 'user_id'), '[]') from public.personal_records r where r.user_id = me),
    'achievements', (select coalesce(jsonb_agg(jsonb_build_object('id', u.achievement_id, 'unlockedAt', u.unlocked_at)), '[]')
                       from public.user_achievements u where u.user_id = me),
    'friends', public.list_friends(),
    'battles', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'mode', b.mode, 'type', b.type, 'status', b.status,
                  'createdAt', b.created_at, 'result', b.result, 'won', b.winner = me)), '[]')
                  from public.battles b where me in (b.player_a, b.player_b)),
    'trophyLedger', (select coalesce(jsonb_agg(to_jsonb(l) - 'user_id' order by l.created_at), '[]') from public.trophy_ledger l where l.user_id = me),
    'clan', (select jsonb_build_object('clanId', m.clan_id, 'role', m.role, 'joinedAt', m.joined_at) from public.clan_members m where m.user_id = me),
    'clanMessages', (select coalesce(jsonb_agg(jsonb_build_object('clanId', c.clan_id, 'body', c.body, 'createdAt', c.created_at)), '[]')
                       from public.clan_messages c where c.user_id = me),
    'notificationPrefs', (select prefs from public.notification_prefs where user_id = me),
    'entitlements', (select coalesce(jsonb_agg(to_jsonb(e) - 'user_id'), '[]') from public.entitlements e where e.user_id = me));
  return t;
end $$;

-- ---------------------------------------------------------------------------
-- Account deletion (Apple 5.1.1(v), doc 16 §4). Needs a sign-in within the last 15 minutes (JWT iat).
-- Clan leadership is handed over first; battles keep the username snapshot ("Deleted user" when null).
-- Store subscriptions are NOT cancelled here — the app links to the store's subscription management.
-- ---------------------------------------------------------------------------
create table public.account_deletions (
  id bigint generated always as identity primary key,
  user_hash text not null,               -- md5 of the user id: proves the deletion happened without keeping the id
  deleted_at timestamptz not null default now()
);
alter table public.account_deletions enable row level security;
revoke all on public.account_deletions from anon, authenticated;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
  v_iat bigint := nullif(current_setting('request.jwt.claims', true)::jsonb->>'iat', '')::bigint;
begin
  if v_iat is null or v_iat < extract(epoch from now() - interval '15 minutes') then
    raise exception 'please sign in again first' using errcode = '42501', hint = 'reauth_required';
  end if;
  if exists (select 1 from public.clan_members where user_id = me) then perform public.leave_clan(); end if;
  delete from public.matchmaking_queue where user_id = me;
  update public.battles set status = 'cancelled', ended_at = now()
   where me in (player_a, player_b) and status in ('created', 'lobby', 'ready_check');
  insert into public.account_deletions (user_hash) values (md5(me::text));
  delete from auth.users where id = me;   -- cascades to profiles and every user-owned row
end $$;

-- ---------------------------------------------------------------------------
-- Pushly Pro (doc 13 §2): RevenueCat webhook → entitlements → profiles.is_pro. Cosmetic / comfort only.
-- ---------------------------------------------------------------------------
create table public.entitlements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  entitlement text not null,
  active boolean not null,
  product_id text,
  store text,
  period_type text,
  expires_at timestamptz,
  will_renew boolean,
  last_event_id text,
  last_event_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, entitlement)
);
alter table public.entitlements enable row level security;
revoke insert, update, delete, truncate on public.entitlements from anon, authenticated;
revoke all on public.entitlements from anon;
create policy entitlements_own on public.entitlements for select to authenticated using (user_id = auth.uid());

create table public.revenuecat_events (
  id text primary key,                   -- RevenueCat event id (idempotency)
  user_id uuid,
  type text not null,
  payload jsonb not null,
  received_at timestamptz not null default now()
);
alter table public.revenuecat_events enable row level security;
revoke all on public.revenuecat_events from anon, authenticated;

-- One RevenueCat webhook event (https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields).
-- Returns "applied" | "duplicate" | "ignored" | "unknown_user".
create or replace function public.apply_entitlement_event(e jsonb) returns text
language plpgsql security definer set search_path = public, app as $$
declare
  v_id text := e->>'id';
  v_type text := e->>'type';
  v_uid uuid;
  v_exp timestamptz := case when e ? 'expiration_at_ms' and e->>'expiration_at_ms' is not null
                            then to_timestamp((e->>'expiration_at_ms')::bigint / 1000.0) end;
  v_at timestamptz := to_timestamp(coalesce((e->>'event_timestamp_ms')::bigint, (extract(epoch from now()) * 1000)::bigint) / 1000.0);
  v_active boolean;
  v_ent text;
begin
  begin
    v_uid := (e->>'app_user_id')::uuid;
  exception when invalid_text_representation then
    v_uid := null;
  end;
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    -- anonymous RevenueCat ids ($RCAnonymousID…) or deleted accounts
    insert into public.revenuecat_events (id, user_id, type, payload) values (coalesce(v_id, md5(e::text)), null, v_type, e)
    on conflict do nothing;
    return 'unknown_user';
  end if;
  insert into public.revenuecat_events (id, user_id, type, payload) values (coalesce(v_id, md5(e::text)), v_uid, v_type, e)
  on conflict do nothing;
  if not found then return 'duplicate'; end if;
  if v_type not in ('INITIAL_PURCHASE', 'RENEWAL', 'PRODUCT_CHANGE', 'UNCANCELLATION', 'NON_RENEWING_PURCHASE', 'CANCELLATION',
                    'EXPIRATION', 'BILLING_ISSUE', 'SUBSCRIPTION_PAUSED', 'TRANSFER', 'SUBSCRIPTION_EXTENDED', 'TEMPORARY_ENTITLEMENT_GRANT') then
    return 'ignored';
  end if;
  -- Active until the expiration date (CANCELLATION / BILLING_ISSUE keep access until then); EXPIRATION ends it.
  v_active := v_type <> 'EXPIRATION' and (v_exp is null or v_exp > now());
  for v_ent in select jsonb_array_elements_text(case when jsonb_typeof(e->'entitlement_ids') = 'array' then e->'entitlement_ids'
                                                     else jsonb_build_array(coalesce(e->>'entitlement_id', 'pro')) end) loop
    insert into public.entitlements as x (user_id, entitlement, active, product_id, store, period_type, expires_at, will_renew,
                                          last_event_id, last_event_at, updated_at)
    values (v_uid, v_ent, v_active, e->>'product_id', e->>'store', e->>'period_type', v_exp,
            v_type not in ('CANCELLATION', 'EXPIRATION', 'BILLING_ISSUE'), v_id, v_at, now())
    on conflict (user_id, entitlement) do update set active = excluded.active, product_id = excluded.product_id,
      store = excluded.store, period_type = excluded.period_type, expires_at = excluded.expires_at,
      will_renew = excluded.will_renew, last_event_id = excluded.last_event_id, last_event_at = excluded.last_event_at,
      updated_at = now()
     where x.last_event_at is null or excluded.last_event_at >= x.last_event_at;   -- out-of-order events never undo newer ones
  end loop;
  update public.profiles set is_pro = exists (select 1 from public.entitlements x where x.user_id = v_uid and x.entitlement = 'pro'
                                                and x.active and (x.expires_at is null or x.expires_at > now()))
   where id = v_uid;
  return 'applied';
end $$;

-- Daily: expire entitlements whose date passed without an EXPIRATION event (webhook missed).
create or replace function app.expire_entitlements(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_n int;
begin
  update public.entitlements set active = false, updated_at = now_at where active and expires_at < now_at - interval '1 day';
  get diagnostics v_n = row_count;
  update public.profiles p set is_pro = false where p.is_pro and not exists (
    select 1 from public.entitlements x where x.user_id = p.id and x.entitlement = 'pro' and x.active);
  return v_n;
end $$;

-- Pro perk (doc 13 §2): up to 2 streak freezes refilled monthly — granted via streak_freeze_grants on the 1st.
create or replace function app.refill_pro_freezes(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_n int;
begin
  insert into public.streak_freeze_grants (user_id, granted_on, count, source)
  select p.id, (now_at at time zone coalesce(p.timezone, 'UTC'))::date, 2, 'pro:' || to_char(now_at at time zone 'UTC', 'YYYY-MM')
    from public.profiles p
   where p.is_pro and not exists (select 1 from public.streak_freeze_grants g where g.user_id = p.id
                                    and g.source = 'pro:' || to_char(now_at at time zone 'UTC', 'YYYY-MM'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

do $$
declare f text;
begin
  foreach f in array array['report(jsonb, text, text)', 'export_my_data()', 'delete_my_account()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.apply_entitlement_event(jsonb) from public, anon, authenticated;
grant execute on function public.apply_entitlement_event(jsonb) to service_role;
grant execute on all functions in schema app to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then return; end if;
  perform cron.schedule('pushly-entitlements', '40 2 * * *', 'select app.expire_entitlements()');
  perform cron.schedule('pushly-pro-freezes', '20 0 1 * *', 'select app.refill_pro_freezes()');
end $$;
