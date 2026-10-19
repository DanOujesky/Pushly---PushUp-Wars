-- 0004 — fix: 0003 seeded min_supported_version 1.0.0, which blocked the 0.1.0 dev builds with "Update required".
-- During development nothing is blocked; raise this only when a release must force an update (doc 03 §7).
update public.app_config
set value = '{"ios": "0.0.0", "android": "0.0.0"}'::jsonb
where key = 'min_supported_version';
