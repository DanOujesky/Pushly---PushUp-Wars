-- 0033 — ghost battles removed from the app (D-076). Practice bots and the arena bot keep using the same timeline
-- machinery (ghost_runs rows with bot_level), but battles between people no longer become someone's ghost, and the
-- runs already recorded from people are deleted (nobody can race them any more).

drop trigger if exists battles_settled_ghosts on public.battles;
drop function if exists app.on_battle_settled_ghosts();

delete from public.ghost_runs g
 where g.user_id is not null
   and not exists (select 1 from public.battles b where b.ghost_run_id = g.id);
