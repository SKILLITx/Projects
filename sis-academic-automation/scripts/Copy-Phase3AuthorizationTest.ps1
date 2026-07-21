[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
function ConvertTo-SqlLiteral([string]$Value) {
  return "'" + $Value.Replace("'", "''") + "'"
}

$Email = (Read-Host 'Staff Auth email to test').Trim()
if ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'Email format is invalid.' }
$InstitutionCode = (Read-Host 'Institution code to test, for example DMU').Trim().ToUpperInvariant()
$CampusCode = (Read-Host 'Campus code to test, or leave blank for institution scope').Trim().ToUpperInvariant()

$EmailSql = ConvertTo-SqlLiteral $Email
$InstitutionSql = ConvertTo-SqlLiteral $InstitutionCode
$CampusCondition = if ($CampusCode) {
  "and upper(c.code) = upper(" + (ConvertTo-SqlLiteral $CampusCode) + ")"
} else {
  ""
}

$Sql = @"
begin;

create temporary table phase3_test_context on commit drop as
select
  au.id as auth_user_id,
  sp.id as staff_profile_id,
  i.id as institution_id,
  (
    select c.id
    from public.campuses c
    where c.institution_id = i.id
      $CampusCondition
    order by c.code
    limit 1
  ) as campus_id
from auth.users au
join public.staff_profiles sp on sp.auth_user_id = au.id
cross join public.institutions i
where lower(au.email) = lower($EmailSql)
  and upper(i.code) = upper($InstitutionSql)
limit 1;

grant select on phase3_test_context to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select auth_user_id from phase3_test_context),
    'role', 'authenticated',
    'email', $EmailSql
  )::text,
  true
);

set local role authenticated;

with rpc_result as (
  select public.rpc_get_dashboard_snapshot(
    jsonb_build_object(
      'correlation_id', gen_random_uuid(),
      'institution_id', (select institution_id from phase3_test_context),
      'campus_id', (select campus_id from phase3_test_context),
      'payload', jsonb_build_object('term_id', null)
    )
  ) as payload
)
select jsonb_build_object(
  'success',
    (select count(*) > 0 from public.staff_profiles)
    and (select count(*) > 0 from public.institutions)
    and coalesce((select (payload->>'success')::boolean from rpc_result), false),
  'suite', 'phase3-authenticated-authorization-verification',
  'staff_profiles_visible', (select count(*) from public.staff_profiles),
  'role_assignments_visible', (select count(*) from public.role_assignments),
  'institutions_visible', (select count(*) from public.institutions),
  'campuses_visible', (select count(*) from public.campuses),
  'dashboard_rpc_success', (select (payload->>'success')::boolean from rpc_result),
  'dashboard_operation', (select payload->>'operation' from rpc_result)
) as result;

rollback;
"@

Set-Clipboard -Value $Sql
Write-Host 'Phase 3 authorization verification SQL copied to the clipboard.'
