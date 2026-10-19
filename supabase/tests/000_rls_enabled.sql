-- CLAUDE.md §4.2: every table has RLS enabled. This test fails as soon as a migration adds a table without it.
begin;
select plan(1);

select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  '',
  'all public tables have row level security enabled'
);

select * from finish();
rollback;
