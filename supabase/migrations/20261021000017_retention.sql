-- 0017 — retention promised in docs/legal/privacy-policy.md: clan chat 90 days, battle rep events 180 days,
-- resolved reports 2 years, matchmaking leftovers. Extends app.housekeeping (daily cron from 0013).
create or replace function app.housekeeping(now_at timestamptz default now()) returns void
language plpgsql security definer set search_path = public, app as $$
begin
  delete from public.rep_session_logs l using public.rep_sessions s
   where s.id = l.session_id and s.received_at < now_at - interval '90 days';   -- raw logs: 90 days (doc 16)
  delete from public.push_outbox where sent_at < now_at - interval '30 days';
  delete from public.rate_limits where window_start < now_at - interval '2 days';
  delete from public.activity_events where created_at < now_at - interval '30 days';
  delete from public.clan_messages where created_at < now_at - interval '90 days';
  delete from public.battle_events e using public.battles b
   where b.id = e.battle_id and b.status in ('settled', 'cancelled', 'void') and b.created_at < now_at - interval '180 days';
  delete from public.reports where status <> 'open' and created_at < now_at - interval '2 years';
  delete from public.battle_invites where created_at < now_at - interval '7 days';
  delete from public.matchmaking_queue where joined_at < now_at - interval '1 hour';
  delete from public.revenuecat_events where received_at < now_at - interval '400 days';
end $$;
