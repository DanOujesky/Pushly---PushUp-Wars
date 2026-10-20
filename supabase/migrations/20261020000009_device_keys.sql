-- 0009 — device keys for signed rep logs (doc 06 §3, roadmap P4-02 part 1).
-- Each install makes a P-256 key pair (iOS Secure Enclave / Android Keystore) and registers the public key here.
-- submit-rep-session verifies every signed log with it. Hardware attestation (App Attest / Play Integrity) is part 2
-- and will fill attest_key_id / attested_at; until then a key proves "same install", not "genuine app".

create unique index devices_user_key_idx on public.devices(user_id, public_key) where public_key is not null;

-- Registers (or refreshes) the caller's device by public key; idempotent, so apps call it on every launch.
-- p: {platform, publicKey (base64 SPKI DER, P-256), model, osVersion, appVersion}. Returns the device id.
create or replace function public.register_device(p jsonb) returns uuid
language plpgsql security definer set search_path = public, app as $$
declare
  uid uuid := auth.uid();
  key text := p->>'publicKey';
  v_id uuid;
  active int;
begin
  if uid is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  if p->>'platform' not in ('ios', 'android') then
    raise exception 'invalid platform' using errcode = '22023';
  end if;
  -- A P-256 SPKI is 91 bytes = 124 base64 characters; allow a little slack for other encodings of the same key.
  if key is null or key !~ '^[A-Za-z0-9+/]{100,200}={0,2}$' then
    raise exception 'invalid public key' using errcode = '22023';
  end if;
  select d.id into v_id from public.devices d where d.user_id = uid and d.public_key = key;
  if v_id is null then
    select count(*) into active from public.devices where user_id = uid and revoked_at is null;
    if active >= 10 then
      -- Keep the newest 9 active devices; the oldest is retired (its logs stay valid).
      update public.devices set revoked_at = now()
       where devices.id = (select d.id from public.devices d where d.user_id = uid and d.revoked_at is null
                    order by coalesce(d.last_seen_at, d.created_at) limit 1);
    end if;
    insert into public.devices (user_id, platform, model, os_version, app_version, public_key, last_seen_at)
    values (uid, (p->>'platform')::public.platform_t, left(p->>'model', 80), left(p->>'osVersion', 40),
            left(p->>'appVersion', 40), key, now())
    returning devices.id into v_id;
  else
    update public.devices set model = left(p->>'model', 80), os_version = left(p->>'osVersion', 40),
      app_version = left(p->>'appVersion', 40), last_seen_at = now(), revoked_at = null
     where devices.id = v_id;
  end if;
  return v_id;
end $$;
revoke all on function public.register_device(jsonb) from public, anon;
grant execute on function public.register_device(jsonb) to authenticated;
