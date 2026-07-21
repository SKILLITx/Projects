-- Workflow 04 hosted verification. Read-only.
with checks as (
  select 'migration_function_results_actor' as check_name,
         to_regprocedure('app.results_staff_actor(jsonb)') is not null as passed
  union all
  select 'marks_decision_rpc',
         to_regprocedure('public.rpc_decide_marks_batch(jsonb)') is not null
  union all
  select 'correction_form_rpc',
         to_regprocedure('public.rpc_request_mark_correction_from_form(jsonb)') is not null
  union all
  select 'correction_decision_rpc',
         to_regprocedure('public.rpc_decide_mark_correction(jsonb)') is not null
  union all
  select 'publish_results_rpc',
         to_regprocedure('public.rpc_publish_results(jsonb)') is not null
  union all
  select 'configured_course_calculation',
         to_regprocedure('app.calculate_course_result(uuid,uuid,uuid)') is not null
  union all
  select 'configured_academic_recalculation',
         to_regprocedure('app.recalculate_academic_record(uuid,uuid,uuid)') is not null
  union all
  select 'correction_evidence_column',
         exists (
           select 1
           from information_schema.columns
           where table_schema = 'public'
             and table_name = 'mark_correction_requests'
             and column_name = 'evidence_url'
         )
  union all
  select 'service_role_form_wrapper_grant',
         has_function_privilege(
           'service_role',
           'public.rpc_request_mark_correction_from_form(jsonb)',
           'EXECUTE'
         )
  union all
  select 'authenticated_cannot_execute_form_wrapper',
         not has_function_privilege(
           'authenticated',
           'public.rpc_request_mark_correction_from_form(jsonb)',
           'EXECUTE'
         )
),
pilot as (
  select jsonb_build_object(
    'latest_finalized_batch_id', mb.id,
    'institution_id', mb.institution_id,
    'campus_id', mb.campus_id,
    'course_offering_id', mb.offering_id,
    'section_id', mb.section_id,
    'batch_status', mb.batch_status,
    'version_number', mb.version_number,
    'validation_summary', mb.validation_summary
  ) as value
  from public.marks_batches mb
  where mb.batch_status = 'finalized'
  order by mb.created_at desc
  limit 1
)
select jsonb_build_object(
  'status', case
    when bool_and(checks.passed) then 'PASS'
    else 'FAIL'
  end,
  'checks', jsonb_agg(
    jsonb_build_object(
      'check', checks.check_name,
      'passed', checks.passed
    )
    order by checks.check_name
  ),
  'pilot', coalesce(
    (select value from pilot),
    '{}'::jsonb
  )
) as workflow04_hosted_verification
from checks;
