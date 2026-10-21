-- 0013 — scheduled jobs (pg_cron + pg_net), doc 11 migration order. Skipped where the extensions don't exist (local
-- sandboxes); on Supabase both are available. push-send needs two Vault secrets (docs/RELEASING.md → Push):
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service role key>', 'service_role_key');

-- Housekeeping in one function so it can be tested without pg_cron.
create or replace function app.housekeeping(now_at timestamptz default now()) returns void
language plpgsql security definer set search_path = public, app as $$
begin
  delete from public.rep_session_logs l using public.rep_sessions s
   where s.id = l.session_id and s.received_at < now_at - interval '90 days';   -- raw logs: 90 days (doc 16)
  delete from public.push_outbox where sent_at < now_at - interval '30 days';
  delete from public.rate_limits where window_start < now_at - interval '2 days';
  delete from public.activity_events where created_at < now_at - interval '30 days';
end $$;

-- Wake results for users who never reopen the app: decide missed days (same rules as on upload).
create or replace function app.settle_all_wake_days(now_at timestamptz default now()) returns int
language plpgsql security definer set search_path = public, app as $$
declare
  v_uid uuid;
  v_n int := 0;
begin
  for v_uid in select distinct user_id from public.alarm_schedules where counts_for_challenge loop
    perform app.settle_wake_days(v_uid, now_at);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Calls the push-send function (needs the Vault secrets above; silently does nothing without them).
create or replace function app.kick_push_send() returns void
language plpgsql security definer set search_path = public, app as $$
declare
  v_url text;
  v_key text;
begin
  if to_regclass('vault.decrypted_secrets') is null or to_regproc('net.http_post') is null then return; end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'project_url'$q$ into v_url;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'$q$ into v_key;
  if v_url is null or v_key is null then return; end if;
  if not exists (select 1 from public.push_outbox where sent_at is null and send_after <= now() and attempts < 5) then return; end if;
  execute 'select net.http_post(url := $1, headers := $2, body := $3)'
    using v_url || '/functions/v1/push-send',
          jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          '{}'::jsonb;
end $$;

do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron not available — scheduled jobs skipped (local sandbox)';
    return;
  end if;
  create extension if not exists pg_cron;
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
  perform cron.schedule('pushly-leaderboards', '* * * * *', 'select app.refresh_leaderboards()');
  perform cron.schedule('pushly-push-send', '* * * * *', 'select app.kick_push_send()');
  perform cron.schedule('pushly-settle-wakes', '*/15 * * * *', 'select app.settle_all_wake_days()');
  perform cron.schedule('pushly-housekeeping', '17 3 * * *', 'select app.housekeeping()');
end $$;
