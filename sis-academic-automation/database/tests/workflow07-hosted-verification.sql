with functions as (
  select
    p.proname,
    pg_get_functiondef(p.oid) as definition,
    has_function_privilege(
      'authenticated',
      format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)),
      'EXECUTE'
    ) as authenticated_can_execute
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('rpc_search_students','rpc_get_dashboard_snapshot')
    and pg_get_function_identity_arguments(p.oid) = 'p_request jsonb'
)
select jsonb_build_object(
  'status',
    case when
      (select count(*) from functions) = 2
      and (select bool_and(authenticated_can_execute) from functions)
      and (select bool_and(
        definition like '%app.can_administer_institution%'
        and definition like '%app.can_access_campus%'
      ) from functions)
      and (select definition from functions where proname = 'rpc_search_students')
        like '%student_number%'
      and (select definition from functions where proname = 'rpc_search_students')
        not like '%date_of_birth%'
      and (select definition from functions where proname = 'rpc_search_students')
        not like '%cnic_hash%'
      and (select definition from functions where proname = 'rpc_get_dashboard_snapshot')
        like '%grade_distribution%'
      and (select definition from functions where proname = 'rpc_get_dashboard_snapshot')
        like '%section_capacity_snapshot%'
    then 'PASS'
    else 'FAIL'
    end,
  'checks', jsonb_build_object(
    'rpc_count', (select count(*) from functions),
    'authenticated_execute', coalesce((select bool_and(authenticated_can_execute) from functions),false),
    'scope_checks_present', coalesce((
      select bool_and(
        definition like '%app.can_administer_institution%'
        and definition like '%app.can_access_campus%'
      ) from functions
    ),false),
    'search_sanitized', coalesce((
      select definition like '%student_number%'
         and definition not like '%date_of_birth%'
         and definition not like '%cnic_hash%'
      from functions where proname = 'rpc_search_students'
    ),false),
    'dashboard_sections', coalesce((
      select definition like '%section_capacity_snapshot%'
      from functions where proname = 'rpc_get_dashboard_snapshot'
    ),false),
    'dashboard_grades', coalesce((
      select definition like '%grade_distribution%'
      from functions where proname = 'rpc_get_dashboard_snapshot'
    ),false)
  )
) as workflow07_hosted_verification;
