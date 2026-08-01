-- Workflow 04 Results Approval and Publication preflight.
-- Read-only inspection apart from temporary pg_temp helper functions.
-- Returns one JSON object containing the exact live database contract needed
-- to build the Workflow 04 migration, RPC wrapper and n8n workflow.

create or replace function pg_temp.sis_sample_table(
  p_schema text,
  p_table text,
  p_limit integer default 5
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  if to_regclass(format('%I.%I', p_schema, p_table)) is null then
    return '[]'::jsonb;
  end if;

  execute format(
    'select coalesce(jsonb_agg(to_jsonb(sample_row)), ''[]''::jsonb)
       from (
         select *
           from %I.%I
          limit %s
       ) sample_row',
    p_schema,
    p_table,
    greatest(1, least(coalesce(p_limit, 5), 20))
  )
  into v_result;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

with target_tables(table_schema, table_name) as (
  values
    ('public', 'marks_batches'),
    ('public', 'student_marks'),
    ('public', 'assessments'),
    ('public', 'assessment_components'),
    ('public', 'grading_policies'),
    ('public', 'grade_scales'),
    ('public', 'academic_standing_rules'),
    ('public', 'marks_approval_history'),
    ('public', 'mark_correction_requests'),
    ('public', 'course_results'),
    ('public', 'semester_results'),
    ('public', 'cumulative_results'),
    ('public', 'academic_standing_history'),
    ('public', 'students'),
    ('public', 'enrollments'),
    ('public', 'course_offerings'),
    ('public', 'sections'),
    ('public', 'terms'),
    ('public', 'semesters'),
    ('public', 'staff_profiles'),
    ('public', 'role_assignments'),
    ('public', 'notification_outbox'),
    ('audit', 'audit_logs'),
    ('ops', 'workflow_runs')
),
columns_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table_schema', c.table_schema,
        'table_name', c.table_name,
        'ordinal_position', c.ordinal_position,
        'column_name', c.column_name,
        'data_type', c.data_type,
        'udt_schema', c.udt_schema,
        'udt_name', c.udt_name,
        'is_nullable', c.is_nullable,
        'column_default', c.column_default
      )
      order by c.table_schema, c.table_name, c.ordinal_position
    ),
    '[]'::jsonb
  ) as value
  from information_schema.columns c
  join target_tables t
    on t.table_schema = c.table_schema
   and t.table_name = c.table_name
),
constraints_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table_schema', n.nspname,
        'table_name', rel.relname,
        'constraint_name', con.conname,
        'constraint_type', con.contype,
        'definition', pg_get_constraintdef(con.oid, true)
      )
      order by n.nspname, rel.relname, con.conname
    ),
    '[]'::jsonb
  ) as value
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace n on n.oid = rel.relnamespace
  join target_tables t
    on t.table_schema = n.nspname
   and t.table_name = rel.relname
),
indexes_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table_schema', schemaname,
        'table_name', tablename,
        'index_name', indexname,
        'index_definition', indexdef
      )
      order by schemaname, tablename, indexname
    ),
    '[]'::jsonb
  ) as value
  from pg_indexes i
  join target_tables t
    on t.table_schema = i.schemaname
   and t.table_name = i.tablename
),
policies_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schema_name', schemaname,
        'table_name', tablename,
        'policy_name', policyname,
        'permissive', permissive,
        'roles', roles,
        'command', cmd,
        'using_expression', qual,
        'check_expression', with_check
      )
      order by schemaname, tablename, policyname
    ),
    '[]'::jsonb
  ) as value
  from pg_policies p
  join target_tables t
    on t.table_schema = p.schemaname
   and t.table_name = p.tablename
),
enum_types as (
  select distinct c.udt_schema, c.udt_name
  from information_schema.columns c
  join target_tables t
    on t.table_schema = c.table_schema
   and t.table_name = c.table_name
  where c.data_type = 'USER-DEFINED'
),
enums_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'enum_schema', n.nspname,
        'enum_name', typ.typname,
        'enum_label', e.enumlabel,
        'sort_order', e.enumsortorder
      )
      order by n.nspname, typ.typname, e.enumsortorder
    ),
    '[]'::jsonb
  ) as value
  from pg_type typ
  join pg_namespace n on n.oid = typ.typnamespace
  join pg_enum e on e.enumtypid = typ.oid
  join enum_types et
    on et.udt_schema = n.nspname
   and et.udt_name = typ.typname
),
functions_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'function_schema', n.nspname,
        'function_name', p.proname,
        'identity_arguments', pg_get_function_identity_arguments(p.oid),
        'result_type', pg_get_function_result(p.oid),
        'security_definer', p.prosecdef,
        'definition', pg_get_functiondef(p.oid)
      )
      order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
    ),
    '[]'::jsonb
  ) as value
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'app', 'private')
    and (
      p.proname ilike '%mark%'
      or p.proname ilike '%result%'
      or p.proname ilike '%grade%'
      or p.proname ilike '%gpa%'
      or p.proname ilike '%cgpa%'
      or p.proname ilike '%standing%'
      or p.proname ilike '%correction%'
      or p.proname ilike '%approval%'
      or p.proname ilike '%service_request%'
      or p.proname ilike '%role%'
      or p.proname ilike '%workflow_run%'
    )
),
latest_finalized_batch as (
  select coalesce(
    (
      select to_jsonb(mb)
      from public.marks_batches mb
      where mb.batch_status::text = 'finalized'
      order by mb.created_at desc
      limit 1
    ),
    '{}'::jsonb
  ) as value
),
samples_json as (
  select jsonb_build_object(
    'marks_batches', pg_temp.sis_sample_table('public', 'marks_batches', 5),
    'student_marks', pg_temp.sis_sample_table('public', 'student_marks', 10),
    'assessments', pg_temp.sis_sample_table('public', 'assessments', 10),
    'assessment_components', pg_temp.sis_sample_table('public', 'assessment_components', 10),
    'grading_policies', pg_temp.sis_sample_table('public', 'grading_policies', 10),
    'grade_scales', pg_temp.sis_sample_table('public', 'grade_scales', 20),
    'academic_standing_rules', pg_temp.sis_sample_table('public', 'academic_standing_rules', 20),
    'marks_approval_history', pg_temp.sis_sample_table('public', 'marks_approval_history', 10),
    'mark_correction_requests', pg_temp.sis_sample_table('public', 'mark_correction_requests', 10),
    'course_results', pg_temp.sis_sample_table('public', 'course_results', 10),
    'semester_results', pg_temp.sis_sample_table('public', 'semester_results', 10),
    'cumulative_results', pg_temp.sis_sample_table('public', 'cumulative_results', 10),
    'academic_standing_history', pg_temp.sis_sample_table('public', 'academic_standing_history', 10),
    'staff_profiles', pg_temp.sis_sample_table('public', 'staff_profiles', 10),
    'role_assignments', pg_temp.sis_sample_table('public', 'role_assignments', 20),
    'notification_outbox', pg_temp.sis_sample_table('public', 'notification_outbox', 10)
  ) as value
)
select jsonb_build_object(
  'generated_at_utc', timezone('utc', now()),
  'database_version', current_setting('server_version'),
  'columns', (select value from columns_json),
  'constraints', (select value from constraints_json),
  'indexes', (select value from indexes_json),
  'policies', (select value from policies_json),
  'enum_values', (select value from enums_json),
  'matching_functions', (select value from functions_json),
  'latest_finalized_marks_batch', (select value from latest_finalized_batch),
  'table_samples', (select value from samples_json)
) as workflow04_preflight;
