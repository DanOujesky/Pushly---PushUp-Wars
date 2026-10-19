-- Tiny subset of pgTAP (plan, ok, is, isnt, throws_ok, lives_ok, finish) for environments where the real
-- pgTAP extension can't be installed. The real Supabase CLI (`supabase test db`) uses real pgTAP; our tests
-- only use functions that exist in both with the same semantics. Output lines follow TAP ("ok N - desc").

create schema if not exists tap;
create table if not exists tap.state (planned int, counter int, failed int);

create or replace function public.plan(n int) returns text language plpgsql as $$
begin
  delete from tap.state; insert into tap.state values (n, 0, 0);
  return '1..' || n;
end $$;

create or replace function tap._emit(passed boolean, description text, diag text default null) returns text
language plpgsql as $$
declare c int;
begin
  update tap.state set counter = counter + 1, failed = failed + (case when passed then 0 else 1 end)
  returning counter into c;
  return (case when passed then 'ok ' else 'not ok ' end) || c || ' - ' || coalesce(description, '')
    || (case when not passed and diag is not null then E'\n# ' || diag else '' end);
end $$;

create or replace function public.ok(passed boolean, description text default null) returns text
language sql as $$ select tap._emit(coalesce(passed, false), description) $$;

create or replace function public.is(have anyelement, want anyelement, description text default null) returns text
language sql as $$
  select tap._emit(have is not distinct from want, description,
                   'have: ' || coalesce(have::text, 'NULL') || ' want: ' || coalesce(want::text, 'NULL'))
$$;

create or replace function public.isnt(have anyelement, want anyelement, description text default null) returns text
language sql as $$
  select tap._emit(have is distinct from want, description, 'both: ' || coalesce(have::text, 'NULL'))
$$;

create or replace function public.throws_ok(sql text, errcode text, errmsg text default null, description text default null)
returns text language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    if errcode is not null and sqlstate <> errcode then
      return tap._emit(false, description, 'expected ' || errcode || ' got ' || sqlstate || ': ' || sqlerrm);
    end if;
    if errmsg is not null and sqlerrm <> errmsg then
      return tap._emit(false, description, 'expected message "' || errmsg || '" got "' || sqlerrm || '"');
    end if;
    return tap._emit(true, description);
  end;
  return tap._emit(false, description, 'no exception raised');
end $$;

create or replace function public.lives_ok(sql text, description text default null) returns text
language plpgsql as $$
begin
  execute sql;
  return tap._emit(true, description);
exception when others then
  return tap._emit(false, description, sqlstate || ': ' || sqlerrm);
end $$;

create or replace function public.finish() returns setof text language plpgsql as $$
declare s tap.state;
begin
  select * into s from tap.state;
  if s.counter <> s.planned then
    return next '# Looks like you planned ' || s.planned || ' tests but ran ' || s.counter;
  end if;
  if s.failed > 0 then return next '# Looks like you failed ' || s.failed || ' test(s)'; end if;
  return;
end $$;

grant usage on schema tap to anon, authenticated, service_role;
grant all on tap.state to anon, authenticated, service_role;
grant execute on all functions in schema tap to anon, authenticated, service_role;
grant execute on function public.plan(int), public.ok(boolean, text), public.throws_ok(text, text, text, text),
  public.lives_ok(text, text), public.finish() to anon, authenticated, service_role;
grant execute on function public.is(anyelement, anyelement, text), public.isnt(anyelement, anyelement, text)
  to anon, authenticated, service_role;
