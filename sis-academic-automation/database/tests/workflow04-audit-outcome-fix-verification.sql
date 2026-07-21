-- Run after applying the Workflow 04 audit-outcome repair.
with function_checks as (
  select
    p.proname as function_name,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'rpc_decide_marks_batch',
      'rpc_request_mark_correction',
      'rpc_decide_mark_correction',
      'rpc_publish_results'
    )
)
select jsonb_build_object(
  'status',
  case
    when count(*) = 4
     and bool_and(definition like '%''success''%')
     and bool_and(definition not like '%v_correlation_id,%''completed''%')
    then 'PASS'
    else 'FAIL'
  end,
  'functions',
  jsonb_agg(
    jsonb_build_object(
      'function_name', function_name,
      'uses_valid_audit_outcome', definition like '%''success''%',
      'contains_invalid_completed_audit_outcome',
        definition like '%v_correlation_id,%''completed''%'
    )
    order by function_name
  )
) as workflow04_audit_outcome_fix_verification
from function_checks;
