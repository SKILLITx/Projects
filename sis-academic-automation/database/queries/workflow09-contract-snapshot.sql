-- Workflow 09 read-only database/RPC contract snapshot.
-- Safe to run in Supabase SQL Editor before applying the Workflow 09 migration.
-- It reads catalog metadata and operational table structure only. It does not
-- return notification recipients, incident details, student records or secrets.

with target_functions as (
  select
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    p.prosecdef as security_definer,
    pg_get_userbyid(p.proowner) as owner_name,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
    has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_execute,
    pg_get_functiondef(p.oid) as definition
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
target_relations(schema_name, relation_name) as (
  values
    ('ops','workflow_runs'),
    ('ops','notification_outbox'),
    ('ops','notification_deliveries'),
    ('ops','incidents'),
    ('ops','incident_events'),
    ('ops','maintenance_runs'),
    ('ops','dashboard_refresh_runs'),
    ('public','institutions'),
    ('public','staff_profiles'),
    ('public','role_assignments'),
    ('public','waitlist_entries'),
    ('public','marks_batches'),
    ('public','sections'),
    ('public','course_offerings'),
    ('public','terms')
),
relation_columns as (
  select
    c.table_schema,
    c.table_name,
    jsonb_agg(
      jsonb_build_object(
        'ordinal', c.ordinal_position,
        'column', c.column_name,
        'type', c.data_type,
        'udt', c.udt_schema || '.' || c.udt_name,
        'nullable', c.is_nullable = 'YES'
      ) order by c.ordinal_position
    ) as columns
  from information_schema.columns c
  join target_relations tr
    on tr.schema_name = c.table_schema
   and tr.relation_name = c.table_name
  group by c.table_schema, c.table_name
),
relation_indexes as (
  select
    i.schemaname as table_schema,
    i.tablename as table_name,
    jsonb_agg(
      jsonb_build_object('name', i.indexname, 'definition', i.indexdef)
      order by i.indexname
    ) as indexes
  from pg_indexes i
  join target_relations tr
    on tr.schema_name = i.schemaname
   and tr.relation_name = i.tablename
  group by i.schemaname, i.tablename
)
select jsonb_pretty(jsonb_build_object(
  'captured_at_utc', timezone('utc', now()),
  'functions', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'schema', schema_name,
        'name', function_name,
        'identity_arguments', identity_arguments,
        'result_type', result_type,
        'security_definer', security_definer,
        'owner', owner_name,
        'authenticated_execute', authenticated_execute,
        'service_role_execute', service_role_execute,
        'definition', definition
      ) order by function_name
    )
    from target_functions
  ), '[]'::jsonb),
  'relations', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'schema', tr.schema_name,
        'name', tr.relation_name,
        'columns', coalesce(rc.columns, '[]'::jsonb),
        'indexes', coalesce(ri.indexes, '[]'::jsonb)
      ) order by tr.schema_name, tr.relation_name
    )
    from target_relations tr
    left join relation_columns rc
      on rc.table_schema = tr.schema_name
     and rc.table_name = tr.relation_name
    left join relation_indexes ri
      on ri.table_schema = tr.schema_name
     and ri.table_name = tr.relation_name
  ), '[]'::jsonb)
)) as workflow09_contract_snapshot;
