-- Read-only catalog verification after tranche 2 is applied.

select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'staff_profiles',
    'role_assignments',
    'campus_assignments',
    'permission_grants'
  )
order by c.relname;

select
  schemaname,
  tablename,
  policyname,
  cmd,
  roles
from pg_policies
where schemaname = 'public'
  and tablename in (
    'institutions',
    'campuses',
    'institution_settings',
    'academic_years',
    'terms',
    'enrollment_periods',
    'staff_profiles',
    'role_assignments',
    'campus_assignments',
    'permission_grants'
  )
order by tablename, policyname;

select
  n.nspname as schema_name,
  p.proname as function_name,
  p.prosecdef as security_definer,
  coalesce(array_to_string(p.proconfig, ','), '') as function_config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'app'
  and p.proname in (
    'current_staff_profile_id',
    'is_super_administrator',
    'has_institution_role',
    'can_access_institution',
    'can_administer_institution',
    'can_access_campus',
    'can_view_staff_profile',
    'has_permission'
  )
order by p.proname;

select
  grantee,
  table_name,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'staff_profiles',
    'role_assignments',
    'campus_assignments',
    'permission_grants'
  )
  and grantee in ('anon', 'authenticated')
order by grantee, table_name, privilege_type;
