-- Workflow 07 compact hosted verification.
-- Run after applying 20260721000200_phase4_workflow07_admin_search_dashboard_complete.sql.

with functions as (
  select
    p.proname,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    pg_get_functiondef(p.oid) as definition,
    has_function_privilege(
      'authenticated',
      p.oid,
      'EXECUTE'
    ) as authenticated_execute,
    has_function_privilege(
      'service_role',
      p.oid,
      'EXECUTE'
    ) as service_role_execute
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('rpc_search_students','rpc_get_dashboard_snapshot','rpc_log_workflow_run')
),
checks as (
  select * from (values
    ('search_signature', exists(select 1 from functions where proname='rpc_search_students' and identity_arguments='p_request jsonb' and result_type='jsonb')),
    ('dashboard_signature', exists(select 1 from functions where proname='rpc_get_dashboard_snapshot' and identity_arguments='p_request jsonb' and result_type='jsonb')),
    ('logging_signature', exists(select 1 from functions where proname='rpc_log_workflow_run' and identity_arguments='p_request jsonb' and result_type='jsonb')),
    ('authenticated_search_execute', coalesce((select authenticated_execute from functions where proname='rpc_search_students'),false)),
    ('authenticated_dashboard_execute', coalesce((select authenticated_execute from functions where proname='rpc_get_dashboard_snapshot'),false)),
    ('service_role_search_blocked', not coalesce((select service_role_execute from functions where proname='rpc_search_students'),true)),
    ('service_role_dashboard_blocked', not coalesce((select service_role_execute from functions where proname='rpc_get_dashboard_snapshot'),true)),
    ('service_role_logging_allowed', coalesce((select service_role_execute from functions where proname='rpc_log_workflow_run'),false)),
    ('search_context_contract', coalesce((select definition like '%{context,institution_id}%' and definition like '%{context,campus_id}%' from functions where proname='rpc_search_students'),false)),
    ('search_types_present', coalesce((select definition like '%identity_reference%' and definition like '%student_number%' and definition like '%VALIDATION_SEARCH_TYPE_UNSUPPORTED%' from functions where proname='rpc_search_students'),false)),
    ('identity_masking_present', coalesce((select definition like '%identity_reference_masked%' and definition like '%extensions.digest%' from functions where proname='rpc_search_students'),false)),
    ('teacher_only_not_authorized', coalesce((select definition not like '%role = ''teacher''%' from functions where proname='rpc_search_students'),false)),
    ('dashboard_zero_safe', coalesce((select definition like '%marks_completion_percent%' and definition like '%coalesce(v_grade_distribution%' and definition like '%coalesce(v_course_capacity%' from functions where proname='rpc_get_dashboard_snapshot'),false)),
    ('dashboard_scope_names', coalesce((select definition like '%institution_name%' and definition like '%campus_name%' and definition like '%term_name%' from functions where proname='rpc_get_dashboard_snapshot'),false)),
    ('read_rpc_has_no_audit_insert', coalesce((select bool_and(definition not like '%insert into audit.audit_logs%') from functions where proname in ('rpc_search_students','rpc_get_dashboard_snapshot')),false)),
    ('student_number_prefix_index', to_regclass('public.students_number_prefix_idx') is not null),
    ('student_name_trigram_index', to_regclass('public.students_full_name_trgm_idx') is not null),
    ('student_email_trigram_index', to_regclass('public.students_primary_email_trgm_idx') is not null),
    ('contact_email_trigram_index', to_regclass('public.student_contacts_email_trgm_idx') is not null),
    ('demo_identity_fixture', exists(select 1 from public.students s where upper(s.student_number)='DMU-0001' and coalesce(s.metadata->>'synthetic','false')='true' and s.cnic_hash is not null))
  ) as v(check_name, passed)
)
select jsonb_pretty(jsonb_build_object(
  'status', case when bool_and(passed) then 'PASS' else 'FAIL' end,
  'checked_at_utc', timezone('utc', now()),
  'passed', count(*) filter (where passed),
  'failed', count(*) filter (where not passed),
  'checks', jsonb_object_agg(check_name, passed order by check_name)
)) as workflow07_verification
from checks;
