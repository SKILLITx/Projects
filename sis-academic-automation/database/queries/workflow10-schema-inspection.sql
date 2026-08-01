-- Workflow 10 read-only schema inspection.
-- Returns metadata only. No data values, secrets, writes or DDL.
with target_relations(schema_name, relation_name) as (
  values
    ('ops','incidents'),
    ('ops','incident_events'),
    ('ops','notification_outbox'),
    ('ops','workflow_runs'),
    ('ops','maintenance_runs')
), relation_metadata as (
  select
    tr.schema_name,
    tr.relation_name,
    c.relrowsecurity as rls_enabled,
    c.relforcerowsecurity as rls_forced,
    has_table_privilege('service_role', format('%I.%I', tr.schema_name, tr.relation_name), 'SELECT') as service_role_select,
    has_table_privilege('authenticated', format('%I.%I', tr.schema_name, tr.relation_name), 'SELECT') as authenticated_select,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'column', a.attname,
        'type', format_type(a.atttypid, a.atttypmod),
        'nullable', not a.attnotnull,
        'ordinal', a.attnum
      ) order by a.attnum)
      from pg_attribute a
      where a.attrelid = c.oid
        and a.attnum > 0
        and not a.attisdropped
    ), '[]'::jsonb) as columns,
    coalesce((
      select jsonb_agg(jsonb_build_object('name', i.indexname, 'definition', i.indexdef) order by i.indexname)
      from pg_indexes i
      where i.schemaname = tr.schema_name and i.tablename = tr.relation_name
    ), '[]'::jsonb) as indexes,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', p.policyname,
        'command', p.cmd,
        'roles', p.roles,
        'using_present', p.qual is not null,
        'check_present', p.with_check is not null
      ) order by p.policyname)
      from pg_policies p
      where p.schemaname = tr.schema_name and p.tablename = tr.relation_name
    ), '[]'::jsonb) as policies
  from target_relations tr
  left join pg_namespace n on n.nspname = tr.schema_name
  left join pg_class c on c.relnamespace = n.oid and c.relname = tr.relation_name and c.relkind in ('r','p')
), enum_metadata as (
  select
    n.nspname as schema_name,
    t.typname as enum_name,
    jsonb_agg(e.enumlabel order by e.enumsortorder) as values
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where (n.nspname, t.typname) in (
    ('ops','incident_severity'),
    ('ops','incident_status'),
    ('ops','job_status'),
    ('ops','workflow_run_status')
  )
  group by n.nspname, t.typname
), config_candidates as (
  select n.nspname as schema_name, c.relname as relation_name, c.relkind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public','app','ops')
    and c.relkind in ('r','p','v','m')
    and c.relname ~* '(config|setting|threshold|policy|cooldown)'
  order by n.nspname, c.relname
)
select jsonb_build_object(
  'snapshot', 'workflow10.schema',
  'checked_at_utc', timezone('utc', now()),
  'relations', coalesce((select jsonb_agg(to_jsonb(rm) order by rm.schema_name, rm.relation_name) from relation_metadata rm), '[]'::jsonb),
  'enums', coalesce((select jsonb_agg(to_jsonb(em) order by em.schema_name, em.enum_name) from enum_metadata em), '[]'::jsonb),
  'configuration_candidates', coalesce((select jsonb_agg(to_jsonb(cc) order by cc.schema_name, cc.relation_name) from config_candidates cc), '[]'::jsonb)
) as workflow10_schema_snapshot;
