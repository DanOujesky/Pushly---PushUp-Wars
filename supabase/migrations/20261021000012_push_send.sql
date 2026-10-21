-- 0012 — push delivery queue API for the push-send Edge Function (doc 12, doc 15 §2, roadmap P6-05).
-- claim_push_batch leases due rows (so overlapping runs never double-send); finish_push records the outcome.

create or replace function public.claim_push_batch(p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = public, app as $$
declare
  v_out jsonb;
begin
  with due as (
    select o.id from public.push_outbox o
     where o.sent_at is null and o.send_after <= now() and o.attempts < 5
     order by o.send_after, o.id
     limit greatest(1, least(p_limit, 500))
     for update skip locked),
  leased as (
    update public.push_outbox o set attempts = o.attempts + 1,
           send_after = now() + make_interval(mins => 2 * power(2, o.attempts)::int)   -- lease + backoff on failure
      from due where o.id = due.id
    returning o.*)
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'userId', l.user_id, 'type', l.type, 'category', l.category, 'payload', l.payload, 'silent', l.silent,
      'collapseKey', l.collapse_key, 'attempts', l.attempts,
      'devices', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'platform', d.platform, 'token', d.push_token))
                             from public.devices d
                            where d.user_id = l.user_id and d.revoked_at is null and d.push_token is not null), '[]'))
      order by l.id), '[]')
    into v_out from leased l;
  return v_out;
end $$;

-- results: [{"id": 1, "ok": true} | {"id": 2, "ok": false, "error": "...", "retry": true}, ...], deadDevices: [uuid]
create or replace function public.finish_push(results jsonb, dead_devices jsonb default '[]') returns void
language plpgsql security definer set search_path = public, app as $$
begin
  update public.push_outbox o set sent_at = now(), last_error = null
    from jsonb_array_elements(results) r
   where o.id = (r->>'id')::bigint and (r->>'ok')::boolean;
  update public.push_outbox o set last_error = left(r->>'error', 500),
         sent_at = case when coalesce((r->>'retry')::boolean, true) and o.attempts < 5 then null else now() end
    from jsonb_array_elements(results) r
   where o.id = (r->>'id')::bigint and not (r->>'ok')::boolean;
  update public.devices d set push_token = null
   where d.id in (select (x #>> '{}')::uuid from jsonb_array_elements(dead_devices) x);
end $$;

revoke all on function public.claim_push_batch(int) from public, anon, authenticated;
revoke all on function public.finish_push(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.claim_push_batch(int) to service_role;
grant execute on function public.finish_push(jsonb, jsonb) to service_role;
