-- Read-only verification for the Supabase SQL Editor.
-- Run only after the migration has been pushed successfully.

select n.nspname as schema_name
from pg_namespace n
where n.nspname in ('app', 'audit', 'ops', 'reporting')
order by n.nspname;

select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'institutions',
    'campuses',
    'institution_settings',
    'academic_years',
    'terms',
    'enrollment_periods'
  )
order by c.relname;

select
  table_name,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
  and table_name in (
    'institutions',
    'campuses',
    'institution_settings',
    'academic_years',
    'terms',
    'enrollment_periods'
  )
order by grantee, table_name, privilege_type;
