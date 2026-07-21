-- Workflow 05 transcript contract snapshot.
-- Read-only. Captures the exact live database contract needed to build the
-- complete n8n workflow without guessing or mutating academic data.

with target_functions as (
  select
    n.nspname as function_schema,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    p.prosecdef as security_definer,
    pg_get_userbyid(p.proowner) as owner_name,
    has_function_privilege('authenticated', p.oid, 'EXECUTE')
      as authenticated_execute,
    has_function_privilege('service_role', p.oid, 'EXECUTE')
      as service_role_execute,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'rpc_create_transcript_request',
      'rpc_get_transcript_model',
      'rpc_record_transcript_document'
    )
),
active_settings as (
  select jsonb_build_object(
    'transcript_setting_id', ts.id,
    'institution_id', ts.institution_id,
    'version', ts.version,
    'effective_from', ts.effective_from,
    'effective_to', ts.effective_to,
    'reference_prefix', ts.reference_prefix,
    'disclaimer', ts.disclaimer,
    'template_configuration', ts.template_configuration,
    'status', ts.status
  ) as value
  from public.transcript_settings ts
  where ts.institution_id =
    'c4bc6568-8032-ff36-a44f-6d9f26262caf'::uuid
    and ts.status = 'active'
    and ts.effective_from <= current_date
    and (ts.effective_to is null or ts.effective_to >= current_date)
  order by ts.version desc
  limit 1
),
pilot_registration as (
  select jsonb_build_object(
    'student_id', s.id,
    'student_number', s.student_number,
    'student_name', s.full_name,
    'student_email', s.primary_email,
    'institution_id', s.institution_id,
    'institution_code', i.code,
    'institution_name', i.name,
    'institution_logo_url', i.logo_url,
    'campus_id', c.id,
    'campus_code', c.code,
    'campus_name', c.name,
    'campus_city', c.city,
    'program_registration_id', spr.id,
    'program_id', p.id,
    'program_code', p.code,
    'program_name', p.name,
    'program_level', p.level_name,
    'registration_status', spr.registration_status,
    'academic_year_id', ay.id,
    'academic_year_code', ay.code,
    'academic_year_name', ay.name,
    'published_course_results',
      (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'course_result_id', cr.id,
              'term_id', cr.term_id,
              'term_code', t.code,
              'term_name', t.name,
              'course_offering_id', cr.course_offering_id,
              'course_code', course.code,
              'course_title', course.title,
              'credit_hours', cr.credit_hours,
              'total_score', cr.total_score,
              'letter_grade', cr.letter_grade,
              'grade_point', cr.grade_point,
              'outcome_code', cr.outcome_code,
              'result_status', cr.result_status,
              'published_at', cr.published_at
            )
            order by t.starts_on, course.code
          ),
          '[]'::jsonb
        )
        from public.course_results cr
        join public.course_offerings co
          on co.id = cr.course_offering_id
        join public.courses course
          on course.id = co.course_id
        join public.terms t
          on t.id = cr.term_id
        where cr.student_id = s.id
          and cr.result_status = 'published'
      ),
    'semester_results',
      (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'semester_result_id', sr.id,
              'term_id', sr.term_id,
              'term_code', t.code,
              'term_name', t.name,
              'attempted_credits', sr.attempted_credits,
              'earned_credits', sr.earned_credits,
              'quality_points', sr.quality_points,
              'gpa', sr.gpa,
              'standing_code', sr.standing_code,
              'at_risk', sr.at_risk,
              'result_status', sr.result_status,
              'published_at', sr.published_at
            )
            order by t.starts_on
          ),
          '[]'::jsonb
        )
        from public.semester_results sr
        join public.terms t on t.id = sr.term_id
        where sr.student_id = s.id
          and sr.program_registration_id = spr.id
          and sr.result_status = 'published'
      ),
    'cumulative_result',
      (
        select jsonb_build_object(
          'cumulative_result_id', cr.id,
          'attempted_credits', cr.attempted_credits,
          'earned_credits', cr.earned_credits,
          'quality_points', cr.quality_points,
          'cgpa', cr.cgpa,
          'standing_code', cr.standing_code,
          'at_risk', cr.at_risk,
          'last_term_id', cr.last_term_id,
          'calculated_at', cr.calculated_at
        )
        from public.cumulative_results cr
        where cr.student_id = s.id
          and cr.program_registration_id = spr.id
        order by cr.calculated_at desc, cr.id
        limit 1
      )
  ) as value
  from public.students s
  join public.institutions i on i.id = s.institution_id
  join public.campuses c on c.id = s.campus_id
  join public.student_program_registrations spr
    on spr.student_id = s.id
   and spr.institution_id = s.institution_id
   and spr.registration_status = 'active'
  join public.programs p on p.id = spr.program_id
  join public.academic_years ay on ay.id = spr.academic_year_id
  where s.student_number = 'DMU-0001'
  order by spr.created_at desc
  limit 1
),
table_counts as (
  select jsonb_build_object(
    'transcript_requests',
      (select count(*)::bigint from public.transcript_requests),
    'transcript_documents',
      (select count(*)::bigint from public.transcript_documents),
    'transcript_delivery_records',
      (select count(*)::bigint from public.transcript_delivery_records),
    'pending_transcript_notifications',
      (
        select count(*)::bigint
        from ops.notification_outbox no
        where no.notification_type = 'transcript.ready'
          and no.job_status in ('pending', 'claimed', 'running', 'failed')
      )
  ) as value
),
required_columns as (
  select
    c.table_schema,
    c.table_name,
    jsonb_agg(
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
    ) as columns
  from information_schema.columns c
  where c.table_schema in ('public', 'ops')
    and c.table_name in (
      'transcript_requests',
      'transcript_documents',
      'transcript_delivery_records',
      'transcript_settings',
      'notification_outbox',
      'notification_deliveries'
    )
  group by c.table_schema, c.table_name
)
select jsonb_build_object(
  'status',
    case
      when (select count(*) from target_functions) = 3
       and (select value from pilot_registration) is not null
       and (select value from active_settings) is not null
      then 'PASS'
      else 'FAIL'
    end,
  'function_contracts',
    (
      select jsonb_agg(
        jsonb_build_object(
          'function_schema', tf.function_schema,
          'function_name', tf.function_name,
          'identity_arguments', tf.identity_arguments,
          'result_type', tf.result_type,
          'security_definer', tf.security_definer,
          'owner', tf.owner_name,
          'authenticated_execute', tf.authenticated_execute,
          'service_role_execute', tf.service_role_execute,
          'definition', tf.definition
        )
        order by tf.function_name
      )
      from target_functions tf
    ),
  'active_transcript_settings',
    (select value from active_settings),
  'pilot_registration',
    (select value from pilot_registration),
  'exact_row_counts',
    (select value from table_counts),
  'required_table_columns',
    (
      select jsonb_agg(
        jsonb_build_object(
          'table_schema', rc.table_schema,
          'table_name', rc.table_name,
          'columns', rc.columns
        )
        order by rc.table_schema, rc.table_name
      )
      from required_columns rc
    ),
  'workflow05_configuration_targets',
    jsonb_build_object(
      'workflow_name',
        'SIS 05 — Transcript Request, Generation and Delivery — Complete',
      'request_webhook_path',
        'staff/rpc_create_transcript_request',
      'delivery_email',
        'zaidrizwan.278@gmail.com',
      'pilot_student_number',
        'DMU-0001',
      'requires_google_docs_template',
        true,
      'requires_drive_folder',
        true,
      'requires_gmail_delivery',
        true
    )
) as workflow05_contract_snapshot;
