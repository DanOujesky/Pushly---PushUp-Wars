-- Local development seed data. Runs after migrations on `supabase db reset`.
-- Never put real user data here.

-- Two demo users for local testing (password-less; sign in via the Studio "impersonate" feature or OTP to Inbucket).
insert into auth.users (id, email)
values
  ('00000000-0000-4000-8000-000000000001', 'ana.demo@pushly.local'),
  ('00000000-0000-4000-8000-000000000002', 'tom.demo@pushly.local')
on conflict (id) do nothing;

update public.profiles set username = 'AnaDemo', birth_year = 2000, country = 'CZ', timezone = 'Europe/Prague',
  onboarding_completed = true
where id = '00000000-0000-4000-8000-000000000001';

update public.profiles set username = 'TomDemo', birth_year = 1998, country = 'SK', timezone = 'Europe/Bratislava',
  onboarding_completed = true
where id = '00000000-0000-4000-8000-000000000002';
