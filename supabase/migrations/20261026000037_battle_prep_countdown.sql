-- 0037 — Time to get ready before a battle (D-081). The countdown used to be 3.5 s from "both ready", so players had
-- no time to get into position. Every battle start (people, bots, ghosts, Arena Bot) now begins 8 s after the
-- countdown is set: ~3 s "GET READY" + a big 5-4-3-2-1 + GO on both phones (server time, doc 07 §4.4).
-- One trigger instead of rewriting the five functions that set `start_at`; a start already in the past (tests, old
-- rows) is left alone.

create or replace function app.battle_prep_ms() returns int language sql immutable as $$ select 8000 $$;

create or replace function app.on_battle_countdown() returns trigger
language plpgsql as $$
begin
  if new.status = 'countdown' and new.start_at is not null and new.start_at > now()
     and new.start_at < now() + make_interval(secs => app.battle_prep_ms() / 1000.0)
     and (tg_op = 'INSERT' or old.start_at is null) then
    new.start_at := now() + make_interval(secs => app.battle_prep_ms() / 1000.0);
  end if;
  return new;
end $$;

drop trigger if exists battles_prep_countdown on public.battles;
create trigger battles_prep_countdown before insert or update of status, start_at on public.battles
  for each row execute function app.on_battle_countdown();
