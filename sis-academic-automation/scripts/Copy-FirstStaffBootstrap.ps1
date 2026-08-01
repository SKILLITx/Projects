[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function ConvertTo-SqlLiteral([string]$Value) {
  return "'" + $Value.Replace("'", "''") + "'"
}

$Email = (Read-Host 'Supabase Auth user email').Trim()
if ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'Email format is invalid.' }

$FullName = (Read-Host 'Staff full name').Trim()
if ([string]::IsNullOrWhiteSpace($FullName)) { throw 'Full name is required.' }

$Role = (Read-Host 'Role: super_administrator, registrar_admin, campus_administrator or teacher').Trim()
$AllowedRoles = @('super_administrator','registrar_admin','campus_administrator','teacher')
if ($AllowedRoles -notcontains $Role) { throw 'Role is invalid.' }

$InstitutionCode = ''
$CampusCode = ''
if ($Role -ne 'super_administrator') {
  $InstitutionCode = (Read-Host 'Institution code, for example DMU or DCS').Trim().ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($InstitutionCode)) { throw 'Institution code is required.' }
}
if ($Role -eq 'campus_administrator') {
  $CampusCode = (Read-Host 'Campus code, for example ISB, FSD, NORTH or SOUTH').Trim().ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($CampusCode)) { throw 'Campus code is required.' }
}

$EmailSql = ConvertTo-SqlLiteral $Email
$NameSql = ConvertTo-SqlLiteral $FullName
$RoleSql = ConvertTo-SqlLiteral $Role
$InstitutionSql = if ($InstitutionCode) { ConvertTo-SqlLiteral $InstitutionCode } else { 'null' }
$CampusSql = if ($CampusCode) { ConvertTo-SqlLiteral $CampusCode } else { 'null' }

$Sql = @"
begin;

do `$bootstrap`$
declare
  v_email text := $EmailSql;
  v_full_name text := $NameSql;
  v_role public.staff_role := $RoleSql::public.staff_role;
  v_institution_code text := $InstitutionSql;
  v_campus_code text := $CampusSql;
  v_auth_user_id uuid;
  v_staff_id uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_role_assignment_id uuid;
begin
  select au.id into v_auth_user_id
  from auth.users au
  where lower(au.email) = lower(v_email)
  order by au.created_at desc
  limit 1;

  if v_auth_user_id is null then
    raise exception 'AUTH_USER_NOT_FOUND: create the Supabase Auth user first.';
  end if;

  if v_role <> 'super_administrator' then
    select i.id into v_institution_id
    from public.institutions i
    where upper(i.code) = upper(v_institution_code)
      and i.status = 'active';

    if v_institution_id is null then
      raise exception 'INSTITUTION_NOT_FOUND';
    end if;
  end if;

  if v_role = 'campus_administrator' then
    select c.id into v_campus_id
    from public.campuses c
    where c.institution_id = v_institution_id
      and upper(c.code) = upper(v_campus_code)
      and c.status = 'active';

    if v_campus_id is null then
      raise exception 'CAMPUS_NOT_FOUND';
    end if;
  end if;

  select sp.id into v_staff_id
  from public.staff_profiles sp
  where lower(sp.email) = lower(v_email)
  limit 1;

  if v_staff_id is null then
    insert into public.staff_profiles (
      auth_user_id, email, full_name, status
    )
    values (
      v_auth_user_id, lower(v_email), v_full_name, 'active'
    )
    returning id into v_staff_id;
  else
    update public.staff_profiles
    set auth_user_id = v_auth_user_id,
        full_name = v_full_name,
        status = 'active',
        updated_at = timezone('utc', now())
    where id = v_staff_id;
  end if;

  select ra.id into v_role_assignment_id
  from public.role_assignments ra
  where ra.staff_profile_id = v_staff_id
    and ra.role = v_role
    and ra.status = 'active'
    and (
      (v_role = 'super_administrator' and ra.institution_id is null)
      or
      (v_role <> 'super_administrator' and ra.institution_id = v_institution_id)
    )
  order by ra.created_at desc
  limit 1;

  if v_role_assignment_id is null then
    insert into public.role_assignments (
      staff_profile_id, institution_id, role, status
    )
    values (
      v_staff_id,
      case when v_role = 'super_administrator' then null else v_institution_id end,
      v_role,
      'active'
    )
    returning id into v_role_assignment_id;
  end if;

  if v_role = 'campus_administrator' and not exists (
    select 1
    from public.campus_assignments ca
    where ca.role_assignment_id = v_role_assignment_id
      and ca.campus_id = v_campus_id
      and ca.status = 'active'
  ) then
    insert into public.campus_assignments (
      role_assignment_id, institution_id, campus_id, status
    )
    values (
      v_role_assignment_id, v_institution_id, v_campus_id, 'active'
    );
  end if;
end;
`$bootstrap`$;

select jsonb_build_object(
  'success', true,
  'suite', 'phase3-first-staff-bootstrap',
  'email', $EmailSql,
  'role', $RoleSql,
  'staff_profile_linked', exists (
    select 1 from public.staff_profiles
    where lower(email) = lower($EmailSql) and auth_user_id is not null
  )
) as result;

commit;
"@

Set-Clipboard -Value $Sql
Write-Host 'First-staff bootstrap SQL copied to the clipboard.'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it once.'
