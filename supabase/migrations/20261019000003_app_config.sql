-- 0003 — remote config & feature flags (doc 03 §7, roadmap P1-07)

create table public.app_config (
  key text primary key,
  value jsonb not null,
  min_app_version text,
  updated_at timestamptz not null default now()
);

create trigger app_config_touch before update on public.app_config
  for each row execute function app.touch_updated_at();

alter table public.app_config enable row level security;

revoke insert, update, delete on public.app_config from anon, authenticated;

create policy app_config_read_all on public.app_config
  for select to anon, authenticated using (true);

insert into public.app_config (key, value) values
  ('min_supported_version', '{"ios": "1.0.0", "android": "1.0.0"}'),
  ('kill_switches', '{"battles": false, "clan_chat": false, "ads": false}'),
  ('rep_engine_overrides', '{}');
