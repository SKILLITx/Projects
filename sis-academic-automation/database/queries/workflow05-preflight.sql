-- Workflow 05: Transcript Request, Generation and Delivery preflight.
-- Read-only. Returns one JSON object containing:
-- 1. current transcript schema/functions;
-- 2. relevant academic source-table structure;
-- 3. counts of any existing transcript records;
-- 4. one published pilot student candidate;
-- 5. current staff actor context.
--
-- No secrets or private authentication tokens are returned.

with
required_transcript_tables(table_schema, table_name) as (
  values
    ('public'::text, 'transcript_requests'::text),
    ('public'::text, 'transcript_documents'::text),
    ('public'::text, 'transcript_delivery_records'::text)
),
source_tables(table_schema, table_name) as (
  values
    ('public'::text, 'students'::text),
    ('public'::text, 'student_program_registrations'::text),
    ('public'::text, 'programs'::text),
    ('public'::text, 'institutions'::text),
    ('public'::text, 'campuses'::text),
    ('public'::text, 'academic_years'::text),
    ('public'::text, 'terms'::text),
    ('public'::text, 'courses'::text),
    ('public'::text, 'course_offerings'::text),
    ('public'::text, 'course_results'::text),
    ('public'::text, 'semester_results'::text),
    ('public'::text, 'cumulative_results'::text),
    ('public'::text, 'academic_standing_history'::text),
    ('public'::text, 'institution_settings'::text)
),
transcript_table_inventory as (
  select
    rt.table_schema,
    rt.table_name,
    to_regclass(format('%I.%I', rt.table_schema, rt.table_name)) is not null
      as exists,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'column_name', c.column_name,
            'ordinal_position', c.ordinal_position,
            'data_type', c.data_type,
            'udt_schema', c.udt_schema,
            'udt_name', c.udt_name,
            'is_nullable', c.is_nullable,
            'column_default', c.column_default
          )
          order by c.ordinal_position
        )
        from information_schema.columns c
        where c.table_schema = rt.table_schema
          and c.table_name = rt.table_name
      ),
      '[]'::jsonb
    ) as columns,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'constraint_name', con.conname,
            'constraint_type', con.contype,
            'definition', pg_get_constraintdef(con.oid, true)
          )
          order by con.conname
        )
        from pg_constraint con
        join pg_class rel on rel.oid = con.conrelid
        join pg_namespace nsp on nsp.oid = rel.relnamespace
        where nsp.nspname = rt.table_schema
          and rel.relname = rt.table_name
      ),
      '[]'::jsonb
    ) as constraints,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'index_name', idx.indexname,
            'index_definition', idx.indexdef
          )
          order by idx.indexname
        )
        from pg_indexes idx
        where idx.schemaname = rt.table_schema
          and idx.tablename = rt.table_name
      ),
      '[]'::jsonb
    ) as indexes,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'policy_name', pol.policyname,
            'command', pol.cmd,
            'roles', pol.roles,
            'using_expression', pol.qual,
            'check_expression', pol.with_check
          )
          order by pol.policyname
        )
        from pg_policies pol
        where pol.schemaname = rt.table_schema
          and pol.tablename = rt.table_name
      ),
      '[]'::jsonb
    ) as policies
  from required_transcript_tables rt
),
source_table_inventory as (
  select
    st.table_schema,
    st.table_name,
    to_regclass(format('%I.%I', st.table_schema, st.table_name)) is not null
      as exists,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'column_name', c.column_name,
            'ordinal_position', c.ordinal_position,
            'data_type', c.data_type,
            'udt_schema', c.udt_schema,
            'udt_name', c.udt_name,
            'is_nullable', c.is_nullable,
            'column_default', c.column_default
          )
          order by c.ordinal_position
        )
        from information_schema.columns c
        where c.table_schema = st.table_schema
          and c.table_name = st.table_name
      ),
      '[]'::jsonb
    ) as columns
  from source_tables st
),
transcript_functions as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'function_schema', n.nspname,
        'function_name', p.proname,
        'identity_arguments', pg_get_function_identity_arguments(p.oid),
        'result_type', pg_get_function_result(p.oid),
        'security_definer', p.prosecdef,
        'owner', pg_get_userbyid(p.proowner),
        'service_role_execute',
          has_function_privilege(
            'service_role',
            p.oid,
            'EXECUTE'
          ),
        'authenticated_execute',
          has_function_privilege(
            'authenticated',
            p.oid,
            'EXECUTE'
          )
      )
      order by n.nspname, p.proname,
        pg_get_function_identity_arguments(p.oid)
    ),
    '[]'::jsonb
  ) as value
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'app', 'reporting')
    and (
      p.proname ilike '%transcript%'
      or pg_get_function_result(p.oid) ilike '%transcript%'
    )
),
transcript_enums as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'enum_schema', n.nspname,
        'enum_name', t.typname,
        'labels',
          (
            select jsonb_agg(e.enumlabel order by e.enumsortorder)
            from pg_enum e
            where e.enumtypid = t.oid
          )
      )
      order by n.nspname, t.typname
    ),
    '[]'::jsonb
  ) as value
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  where t.typtype = 'e'
    and (
      t.typname ilike '%transcript%'
      or t.typname ilike '%document%'
      or t.typname ilike '%delivery%'
      or t.typname ilike '%request%'
    )
),
staff_actor as (
  select jsonb_build_object(
    'staff_profile_id', sp.id,
    'auth_user_id', sp.auth_user_id,
    'email', sp.email,
    'full_name', sp.full_name,
    'status', sp.status,
    'roles',
      coalesce(
        (
          select jsonb_agg(distinct ra.role::text order by ra.role::text)
          from public.role_assignments ra
          where ra.staff_profile_id = sp.id
            and ra.status = 'active'
            and ra.valid_from <= timezone('utc', now())
            and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
        ),
        '[]'::jsonb
      ),
    'institution_ids',
      coalesce(
        (
          select jsonb_agg(distinct ra.institution_id)
          from public.role_assignments ra
          where ra.staff_profile_id = sp.id
            and ra.status = 'active'
            and ra.institution_id is not null
            and ra.valid_from <= timezone('utc', now())
            and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
        ),
        '[]'::jsonb
      )
  ) as value
  from public.staff_profiles sp
  where lower(sp.email) = lower('zaidrizwan.278@gmail.com')
    and sp.status = 'active'
  order by sp.id
  limit 1
),
pilot_student as (
  select jsonb_build_object(
    'student_id', s.id,
    'student_number', s.student_number,
    'full_name', s.full_name,
    'primary_email', s.primary_email,
    'student_status', s.status,
    'institution_id', s.institution_id,
    'campus_id', s.campus_id,
    'published_course_result_count',
      count(distinct cr.id) filter (
        where cr.result_status = 'published'
      ),
    'published_term_count',
      count(distinct sr.term_id) filter (
        where sr.result_status = 'published'
      ),
    'latest_published_gpa',
      (
        select sr2.gpa
        from public.semester_results sr2
        where sr2.student_id = s.id
          and sr2.result_status = 'published'
        order by sr2.published_at desc nulls last,
          sr2.calculated_at desc,
          sr2.id
        limit 1
      ),
    'current_cgpa',
      (
        select cgr.cgpa
        from public.cumulative_results cgr
        where cgr.student_id = s.id
        order by cgr.calculated_at desc, cgr.id
        limit 1
      ),
    'latest_standing_code',
      (
        select cgr.standing_code
        from public.cumulative_results cgr
        where cgr.student_id = s.id
        order by cgr.calculated_at desc, cgr.id
        limit 1
      ),
    'has_incomplete_course',
      exists (
        select 1
        from public.course_results cr2
        where cr2.student_id = s.id
          and cr2.result_status = 'published'
          and cr2.outcome_code = 'incomplete'
      )
  ) as value
  from public.students s
  join public.course_results cr
    on cr.student_id = s.id
   and cr.institution_id = s.institution_id
  left join public.semester_results sr
    on sr.student_id = s.id
   and sr.institution_id = s.institution_id
  where s.student_number = 'DMU-0001'
    and s.primary_email is not null
  group by
    s.id,
    s.student_number,
    s.full_name,
    s.primary_email,
    s.status,
    s.institution_id,
    s.campus_id
  limit 1
),
existing_row_counts as (
  select jsonb_build_object(
    'transcript_requests',
      case
        when to_regclass('public.transcript_requests') is null then null
        else (
          select cls.reltuples::bigint
          from pg_class cls
          join pg_namespace nsp on nsp.oid = cls.relnamespace
          where nsp.nspname = 'public'
            and cls.relname = 'transcript_requests'
        )
      end,
    'transcript_documents',
      case
        when to_regclass('public.transcript_documents') is null then null
        else (
          select cls.reltuples::bigint
          from pg_class cls
          join pg_namespace nsp on nsp.oid = cls.relnamespace
          where nsp.nspname = 'public'
            and cls.relname = 'transcript_documents'
        )
      end,
    'transcript_delivery_records',
      case
        when to_regclass('public.transcript_delivery_records') is null then null
        else (
          select cls.reltuples::bigint
          from pg_class cls
          join pg_namespace nsp on nsp.oid = cls.relnamespace
          where nsp.nspname = 'public'
            and cls.relname = 'transcript_delivery_records'
        )
      end
  ) as value
)
select jsonb_build_object(
  'status',
    case
      when (select value from pilot_student) is null
        then 'FAIL'
      else 'PASS'
    end,
  'required_transcript_tables',
    (
      select jsonb_agg(
        jsonb_build_object(
          'table_schema', table_schema,
          'table_name', table_name,
          'exists', exists,
          'columns', columns,
          'constraints', constraints,
          'indexes', indexes,
          'policies', policies
        )
        order by table_name
      )
      from transcript_table_inventory
    ),
  'source_table_inventory',
    (
      select jsonb_agg(
        jsonb_build_object(
          'table_schema', table_schema,
          'table_name', table_name,
          'exists', exists,
          'columns', columns
        )
        order by table_name
      )
      from source_table_inventory
    ),
  'transcript_functions',
    (select value from transcript_functions),
  'transcript_related_enums',
    (select value from transcript_enums),
  'existing_transcript_row_counts',
    (select value from existing_row_counts),
  'staff_actor',
    (select value from staff_actor),
  'pilot_student',
    (select value from pilot_student),
  'recommended_pilot',
    jsonb_build_object(
      'student_number', 'DMU-0001',
      'requester_email', 'zaidrizwan.278@gmail.com',
      'delivery_email', 'zaidrizwan.278@gmail.com',
      'request_channel', 'staff_portal',
      'document_format', 'PDF'
    )
) as workflow05_preflight;
