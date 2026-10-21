-- Privacy: opting out of ghost runs also deletes the runs already recorded (objection under GDPR art. 21,
-- privacy policy §4/§8), and the app can read the current setting.
create or replace function public.set_ghost_opt_out(opt_out boolean) returns void
language plpgsql security definer set search_path = public, app as $$
declare
  me uuid := app.require_user();
begin
  update public.profiles set ghost_opt_out = opt_out where id = me;
  if opt_out then
    delete from public.ghost_runs where user_id = me;
  end if;
end $$;
revoke all on function public.set_ghost_opt_out(boolean) from public, anon;
grant execute on function public.set_ghost_opt_out(boolean) to authenticated;

create or replace function public.get_privacy_settings() returns jsonb
language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object('ghostOptOut', p.ghost_opt_out)
    from public.profiles p where p.id = app.require_user()
$$;
revoke all on function public.get_privacy_settings() from public, anon;
grant execute on function public.get_privacy_settings() to authenticated;
