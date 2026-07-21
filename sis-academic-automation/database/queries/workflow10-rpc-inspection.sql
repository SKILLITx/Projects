-- Workflow 10 read-only RPC inspection.
-- Definition excerpts are bounded to avoid giant SQL Editor output.
with targets(schema_name, function_name) as (
  values
    ('public','rpc_record_incident'),
    ('ops','upsert_incident'),
    ('public','rpc_log_workflow_run'),
    ('public','rpc_get_operations_snapshot'),
    ('app','exception_rpc_error'),
    ('app','rpc_success'),
    ('app','require_service'),
    ('app','is_service_request')
), functions as (
  select
    t.schema_name,
    t.function_name,
    p.oid,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    p.prosecdef as security_definer,
    has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_execute,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
    encode(extensions.digest(convert_to(pg_get_functiondef(p.oid), 'UTF8'), 'sha256'), 'hex') as definition_sha256,
    left(pg_get_functiondef(p.oid), 8000) as definition_excerpt
  from targets t
  left join pg_namespace n on n.nspname = t.schema_name
  left join pg_proc p on p.pronamespace = n.oid and p.proname = t.function_name
), missing as (
  select t.schema_name, t.function_name
  from targets t
  where not exists (
    select 1 from functions f
    where f.schema_name = t.schema_name
      and f.function_name = t.function_name
      and f.oid is not null
  )
)
select jsonb_build_object(
  'snapshot', 'workflow10.rpc',
  'checked_at_utc', timezone('utc', now()),
  'functions', coalesce((
    select jsonb_agg(jsonb_build_object(
      'schema', f.schema_name,
      'name', f.function_name,
      'identity_arguments', f.identity_arguments,
      'result_type', f.result_type,
      'security_definer', f.security_definer,
      'service_role_execute', f.service_role_execute,
      'authenticated_execute', f.authenticated_execute,
      'definition_sha256', f.definition_sha256,
      'definition_excerpt', f.definition_excerpt
    ) order by f.schema_name, f.function_name)
    from functions f where f.oid is not null
  ), '[]'::jsonb),
  'missing_functions', coalesce((select jsonb_agg(to_jsonb(m) order by m.schema_name, m.function_name) from missing m), '[]'::jsonb)
) as workflow10_rpc_snapshot;
