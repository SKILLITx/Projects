-- Workflow 07 read-only database/RPC contract snapshot.
-- Safe to run in Supabase SQL Editor. It reads catalog metadata only and does
-- not select student, identity, credential, token, or other personal data.
-- Privilege checks use the pg_proc OID overload so named arguments such as
-- "p_request jsonb" are never reparsed as a regprocedure signature.

with target_functions as (
  select
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    p.prosecdef as security_definer,
    pg_get_userbyid(p.proowner) as owner_name,
    has_function_privilege(
      'authenticated',
      p.oid,
      'EXECUTE'
    ) as authenticated_execute,
    has_function_privilege(
      'service_role',
      p.oid,
      'EXECUTE'
    ) as service_role_execute,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'rpc_search_students',
      'rpc_get_dashboard_snapshot',
      'rpc_log_workflow_run'
    )
),
target_relations(schema_name, relation_name) as (
  values
    ('public','students'),
    ('public','student_contacts'),
    ('public','student_program_registrations'),
    ('public','institutions'),
    ('public','campuses'),
    ('public','programs'),
    ('public','terms'),
    ('public','enrollment_requests'),
    ('public','enrollments'),
    ('public','waitlist_entries'),
    ('public','marks_batches'),
    ('public','course_results'),
    ('public','semester_results'),
    ('public','cumulative_results'),
    ('public','transcript_requests'),
    ('ops','notification_outbox'),
    ('ops','workflow_runs'),
    ('ops','incidents'),
    ('public','courses'),
    ('public','course_offerings'),
    ('public','sections')
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
    schemaname as table_schema,
    tablename as table_name,
    jsonb_agg(
      jsonb_build_object('name', indexname, 'definition', indexdef)
      order by indexname
    ) as indexes
  from pg_indexes i
  join target_relations tr
    on tr.schema_name = i.schemaname
   and tr.relation_name = i.tablename
  group by schemaname, tablename
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
)) as workflow07_contract_snapshot;
