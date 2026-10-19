-- 0001 — extensions, private schema, enums (doc 11 §1)
-- pg_cron is enabled in the later cron migration (`0013_cron`, see the migration order in doc 11), not here, so local sandboxes without it can run 0001–0012.

create extension if not exists citext;
create extension if not exists pgcrypto;

-- Private helpers live in schema `app` (not exposed through the API).
create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to service_role;

create type public.platform_t        as enum ('ios','android');
create type public.visibility_t      as enum ('public','friends','private');
create type public.friendship_status as enum ('pending','accepted','blocked');
create type public.session_context   as enum ('wake','battle','training');
create type public.wake_status       as enum ('scheduled','ringing','in_progress','succeeded','failed','missed','skipped','paused','void');
create type public.battle_type       as enum ('quick','friend_ranked','friendly','ghost');
create type public.battle_mode       as enum ('max_reps','best_of_3','speed','turns','endurance');
create type public.battle_status     as enum ('created','lobby','ready_check','countdown','live','round_rest','finished','settled','cancelled','void');
create type public.clan_role         as enum ('leader','co_leader','elder','member');
create type public.join_policy       as enum ('open','request','invite_only');
create type public.war_status        as enum ('scheduled','live','finished');
create type public.flag_severity     as enum ('soft','hard');
create type public.flag_status       as enum ('open','cleared','actioned');

-- Shared trigger: keep updated_at current.
create or replace function app.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;
