-- Workflow 09 compact hosted verification.
-- Run after applying 20260721000300_phase4_workflow09_operations_monitoring.sql.

with functions as (
  select
    p.proname,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    pg_get_functiondef(p.oid) as definition,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
    has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_execute
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'rpc_get_operations_snapshot',
      'rpc_apply_scheduled_maintenance',
      'rpc_record_incident',
      'rpc_log_workflow_run'
    )
),
checks as (
  select * from (values
    ('snapshot_signature',
      exists(select 1 from functions where proname='rpc_get_operations_snapshot'
        and identity_arguments='p_request jsonb' and result_type='jsonb')),
    ('maintenance_signature',
      exists(select 1 from functions where proname='rpc_apply_scheduled_maintenance'
        and identity_arguments='p_request jsonb' and result_type='jsonb')),
    ('snapshot_authenticated_allowed',
      coalesce((select authenticated_execute from functions where proname='rpc_get_operations_snapshot'),false)),
    ('snapshot_service_allowed',
      coalesce((select service_role_execute from functions where proname='rpc_get_operations_snapshot'),false)),
    ('maintenance_authenticated_blocked',
      not coalesce((select authenticated_execute from functions where proname='rpc_apply_scheduled_maintenance'),true)),
    ('maintenance_service_allowed',
      coalesce((select service_role_execute from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('snapshot_zero_safe_sections',
      coalesce((select definition like '%workflow_runs%'
        and definition like '%notifications%'
        and definition like '%incidents%'
        and definition like '%waitlist%'
        and definition like '%marks%'
        and definition like '%backup%'
        and definition like '%retention%'
        and definition like '%by_institution%'
        and definition like '%latest_monitoring_run%'
        and definition like '%latest_maintenance_run%'
        from functions where proname='rpc_get_operations_snapshot'),false)),
    ('snapshot_scope_authorization',
      coalesce((select definition like '%app.is_super_administrator%'
        and definition like '%app.can_administer_institution%'
        and definition like '%AUTH_SCOPE_DENIED%'
        from functions where proname='rpc_get_operations_snapshot'),false)),
    ('maintenance_service_guard',
      coalesce((select definition like '%perform app.require_service()%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_dry_run',
      coalesce((select definition like '%dry_run%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_idempotency',
      coalesce((select definition like '%replayed%'
        and definition like '%maintenance_runs%'
        and definition like '%correlation_id%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_bounded_claim_release',
      coalesce((select definition like '%stale_claim_minutes%'
        and definition like '%attempt_count < max_attempts%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_stale_draft_bound',
      coalesce((select definition like '%stale_draft_days%'
        and definition like '%greatest%'
        and definition like '%30%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_no_delete',
      coalesce((select lower(definition) not like '%delete from%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_alert_outbox',
      coalesce((select definition like '%operations.monitoring.alert%'
        and definition like '%on conflict%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_no_host_command',
      coalesce((select lower(definition) not like '%execute command%'
        and lower(definition) not like '%powershell%'
        from functions where proname='rpc_apply_scheduled_maintenance'),false)),
    ('maintenance_corr_unique_index',
      to_regclass('ops.maintenance_runs_operation_corr_uq') is not null),
    ('workflow_monitoring_index',
      to_regclass('ops.workflow_runs_monitoring_idx') is not null),
    ('notification_monitoring_index',
      to_regclass('ops.notification_outbox_monitoring_idx') is not null),
    ('incident_monitoring_index',
      to_regclass('ops.incidents_monitoring_idx') is not null),
    ('waitlist_monitoring_index',
      to_regclass('public.waitlist_monitoring_idx') is not null),
    ('marks_monitoring_index',
      to_regclass('public.marks_batches_monitoring_idx') is not null)
  ) as v(check_name, passed)
)
select jsonb_pretty(jsonb_build_object(
  'status', case when bool_and(passed) then 'PASS' else 'FAIL' end,
  'checked_at_utc', timezone('utc', now()),
  'passed', count(*) filter (where passed),
  'failed', count(*) filter (where not passed),
  'checks', jsonb_object_agg(check_name, passed order by check_name)
)) as workflow09_verification
from checks;
