-- Phase 4 / Workflow 03 manual marks form integration.
--
-- Adds one service-role-only public wrapper that resolves user-facing codes,
-- verifies the captured teacher email and class assignment, submits the
-- versioned marks batch, detects omitted enrolled students, optionally
-- finalizes a clean batch, and creates one idempotent confirmation
-- notification.
--
-- Existing Phase 2 functions remain unchanged.

begin;

create or replace function public.rpc_submit_marks_from_form(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.form.submit';
  v_correlation_id uuid :=
    coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_idempotency_key text :=
    nullif(btrim(p_request->>'idempotency_key'), '');
  v_payload jsonb := coalesce(p_request->'payload', '{}'::jsonb);

  v_institution_id uuid;
  v_campus_id uuid;
  v_term_id uuid;
  v_offering_id uuid;
  v_section_id uuid;
  v_assessment_id uuid;
  v_staff_profile_id uuid;

  v_lookup_count integer;
  v_marks jsonb;
  v_core_request jsonb;
  v_submit_result jsonb;
  v_finalize_result jsonb;
  v_batch_id uuid;
  v_batch_status public.marks_batch_status;
  v_validation_summary jsonb := '{}'::jsonb;
  v_missing_count integer := 0;
  v_expected_count integer := 0;
  v_submitted_count integer := 0;
  v_error_count integer := 0;
  v_warning_count integer := 0;
  v_finalize_requested boolean := false;
  v_teacher_email text :=
    nullif(lower(btrim(v_payload->>'teacher_email')), '');
begin
  perform app.require_service();

  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_REQUEST_OBJECT_REQUIRED';
  end if;

  if v_idempotency_key is null
     or v_teacher_email is null
     or nullif(btrim(v_payload->>'institution_code'), '') is null
     or nullif(btrim(v_payload->>'campus_code'), '') is null
     or nullif(btrim(v_payload->>'term_code'), '') is null
     or nullif(btrim(v_payload->>'course_offering_code'), '') is null
     or nullif(btrim(v_payload->>'section_code'), '') is null
     or nullif(btrim(v_payload->>'assessment_code'), '') is null
     or jsonb_typeof(v_payload->'marks') <> 'array'
     or jsonb_array_length(v_payload->'marks') = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  v_finalize_requested :=
    lower(btrim(coalesce(v_payload->>'submission_state', 'draft')))
      in ('finalize', 'finalized', 'finalize after validation');

  select count(*)::integer, (array_agg(i.id order by i.id))[1]
    into v_lookup_count, v_institution_id
  from public.institutions i
  where upper(i.code) = upper(btrim(v_payload->>'institution_code'))
    and i.status = 'active';

  if v_lookup_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_INSTITUTION_NOT_FOUND';
  elsif v_lookup_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_INSTITUTION_AMBIGUOUS';
  end if;

  select count(*)::integer, (array_agg(c.id order by c.id))[1]
    into v_lookup_count, v_campus_id
  from public.campuses c
  where c.institution_id = v_institution_id
    and upper(c.code) = upper(btrim(v_payload->>'campus_code'))
    and c.status = 'active';

  if v_lookup_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_CAMPUS_NOT_FOUND';
  elsif v_lookup_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_CAMPUS_AMBIGUOUS';
  end if;

  select count(*)::integer, (array_agg(t.id order by ay.starts_on desc, t.starts_on desc, t.id))[1]
    into v_lookup_count, v_term_id
  from public.terms t
  join public.academic_years ay
    on ay.id = t.academic_year_id
   and ay.institution_id = t.institution_id
  where t.institution_id = v_institution_id
    and upper(t.code) = upper(btrim(v_payload->>'term_code'))
    and t.status = 'active'
    and ay.status = 'active';

  if v_lookup_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_TERM_NOT_FOUND';
  elsif v_lookup_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_TERM_AMBIGUOUS';
  end if;

  select count(*)::integer, (array_agg(co.id order by co.id))[1]
    into v_lookup_count, v_offering_id
  from public.course_offerings co
  where co.institution_id = v_institution_id
    and co.campus_id = v_campus_id
    and co.term_id = v_term_id
    and upper(co.offering_code) =
      upper(btrim(v_payload->>'course_offering_code'))
    and co.status in ('open', 'completed');

  if v_lookup_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_COURSE_OFFERING_NOT_FOUND';
  elsif v_lookup_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_COURSE_OFFERING_AMBIGUOUS';
  end if;

  select count(*)::integer, (array_agg(s.id order by s.id))[1]
    into v_lookup_count, v_section_id
  from public.sections s
  where s.institution_id = v_institution_id
    and s.campus_id = v_campus_id
    and s.offering_id = v_offering_id
    and upper(s.code) = upper(btrim(v_payload->>'section_code'))
    and s.status in ('open', 'completed');

  if v_lookup_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_SECTION_NOT_FOUND';
  elsif v_lookup_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_SECTION_AMBIGUOUS';
  end if;

  select count(*)::integer, (array_agg(a.id order by (a.section_id is not null) desc, a.id))[1]
    into v_lookup_count, v_assessment_id
  from public.assessments a
  where a.institution_id = v_institution_id
    and a.campus_id = v_campus_id
    and a.offering_id = v_offering_id
    and (a.section_id is null or a.section_id = v_section_id)
    and upper(a.code) = upper(btrim(v_payload->>'assessment_code'))
    and a.status = 'active';

  if v_lookup_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_ASSESSMENT_NOT_FOUND';
  elsif v_lookup_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_ASSESSMENT_AMBIGUOUS';
  end if;

  select count(*)::integer, (array_agg(sp.id order by sp.id))[1]
    into v_lookup_count, v_staff_profile_id
  from public.staff_profiles sp
  where lower(sp.email) = v_teacher_email
    and sp.status = 'active';

  if v_lookup_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'AUTH_TEACHER_NOT_FOUND';
  elsif v_lookup_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'AUTH_TEACHER_AMBIGUOUS';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    where ta.staff_profile_id = v_staff_profile_id
      and ta.institution_id = v_institution_id
      and ta.campus_id = v_campus_id
      and ta.offering_id = v_offering_id
      and ta.section_id = v_section_id
      and ta.status = 'active'
      and (ta.valid_from is null or ta.valid_from <= current_date)
      and (ta.valid_to is null or ta.valid_to >= current_date)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'AUTH_TEACHER_ASSIGNMENT_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_payload->'marks') submitted(mark_row)
    where nullif(btrim(submitted.mark_row->>'student_number'), '') is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_STUDENT_NUMBER_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_payload->'marks') submitted(mark_row)
    group by upper(btrim(submitted.mark_row->>'student_number'))
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_DUPLICATE_STUDENT_NUMBER';
  end if;

  select jsonb_agg(
           submitted.mark_row ||
           jsonb_build_object('assessment_id', v_assessment_id)
           order by submitted.ordinality
         )
    into v_marks
  from jsonb_array_elements(v_payload->'marks')
       with ordinality submitted(mark_row, ordinality);

  v_core_request := jsonb_build_object(
    'operation', 'marks.batch.submit',
    'correlation_id', v_correlation_id,
    'idempotency_key', v_idempotency_key,
    'institution_id', v_institution_id,
    'campus_id', v_campus_id,
    'requester', coalesce(p_request->'requester', '{}'::jsonb),
    'submitted_at', p_request->>'submitted_at',
    'source', coalesce(p_request->'source', '{}'::jsonb),
    'payload', jsonb_strip_nulls(jsonb_build_object(
      'course_offering_id', v_offering_id,
      'section_id', v_section_id,
      'staff_profile_id', v_staff_profile_id,
      'teacher_email', v_teacher_email,
      'teacher_notes', nullif(v_payload->>'teacher_notes',''),
      'marks', v_marks
    ))
  );

  v_submit_result := public.rpc_submit_marks_batch(v_core_request);

  if not coalesce((v_submit_result->>'success')::boolean, false) then
    return v_submit_result;
  end if;

  v_batch_id :=
    nullif(v_submit_result#>>'{data,marks_batch_id}', '')::uuid;

  if v_batch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_MARKS_BATCH_ID_MISSING';
  end if;

  insert into public.marks_validation_issues (
    institution_id,
    marks_batch_id,
    issue_code,
    severity,
    student_number,
    assessment_code,
    message,
    details
  )
  select
    v_institution_id,
    v_batch_id,
    'MARKS_STUDENT_MISSING_FROM_SUBMISSION',
    'error',
    s.student_number,
    upper(btrim(v_payload->>'assessment_code')),
    'An actively enrolled student was omitted from the submitted marks batch.',
    jsonb_build_object(
      'course_offering_id', v_offering_id,
      'section_id', v_section_id,
      'assessment_id', v_assessment_id
    )
  from public.enrollments e
  join public.students s
    on s.id = e.student_id
   and s.institution_id = e.institution_id
  where e.institution_id = v_institution_id
    and e.course_offering_id = v_offering_id
    and e.section_id = v_section_id
    and e.enrollment_status = 'active'
    and not exists (
      select 1
      from public.student_marks sm
      where sm.marks_batch_id = v_batch_id
        and sm.assessment_id = v_assessment_id
        and sm.student_id = e.student_id
    )
    and not exists (
      select 1
      from public.marks_validation_issues mvi
      where mvi.marks_batch_id = v_batch_id
        and mvi.issue_code = 'MARKS_STUDENT_MISSING_FROM_SUBMISSION'
        and upper(coalesce(mvi.student_number, '')) =
            upper(coalesce(s.student_number, ''))
        and upper(coalesce(mvi.assessment_code, '')) =
            upper(btrim(v_payload->>'assessment_code'))
    );

  select count(*)::integer
    into v_expected_count
  from public.enrollments e
  where e.institution_id = v_institution_id
    and e.course_offering_id = v_offering_id
    and e.section_id = v_section_id
    and e.enrollment_status = 'active';

  select count(*)::integer
    into v_submitted_count
  from public.student_marks sm
  where sm.marks_batch_id = v_batch_id
    and sm.assessment_id = v_assessment_id;

  select
    count(*) filter (
      where mvi.issue_code = 'MARKS_STUDENT_MISSING_FROM_SUBMISSION'
    )::integer,
    count(*) filter (where mvi.severity = 'error')::integer,
    count(*) filter (where mvi.severity = 'warning')::integer
  into v_missing_count, v_error_count, v_warning_count
  from public.marks_validation_issues mvi
  where mvi.marks_batch_id = v_batch_id;

  update public.marks_batches mb
  set validation_summary =
    coalesce(mb.validation_summary, '{}'::jsonb) ||
    jsonb_build_object(
      'expected_students', v_expected_count,
      'submitted_students', v_submitted_count,
      'missing_students', v_missing_count,
      'error_count', v_error_count,
      'warning_count', v_warning_count
    )
  where mb.id = v_batch_id
  returning mb.batch_status, mb.validation_summary
    into v_batch_status, v_validation_summary;

  if v_finalize_requested then
    v_finalize_result := public.rpc_finalize_marks_batch(
      jsonb_build_object(
        'operation', 'marks.batch.finalize',
        'correlation_id', v_correlation_id,
        'idempotency_key', v_idempotency_key || ':finalize',
        'institution_id', v_institution_id,
        'campus_id', v_campus_id,
        'requester', coalesce(p_request->'requester', '{}'::jsonb),
        'submitted_at', p_request->>'submitted_at',
        'source', coalesce(p_request->'source', '{}'::jsonb),
        'payload', jsonb_build_object('marks_batch_id', v_batch_id)
      )
    );

    if not coalesce((v_finalize_result->>'success')::boolean, false) then
      return v_finalize_result;
    end if;

    v_batch_status :=
      coalesce(
        nullif(v_finalize_result#>>'{data,status}', '')::public.marks_batch_status,
        'finalized'::public.marks_batch_status
      );
  end if;

  insert into ops.notification_outbox (
    institution_id,
    campus_id,
    channel,
    notification_type,
    recipient_address,
    recipient_name,
    subject,
    template_code,
    payload,
    correlation_id,
    idempotency_key,
    job_status,
    priority
  )
  values (
    v_institution_id,
    v_campus_id,
    'email',
    'marks.submission.confirmed',
    v_teacher_email,
    (
      select sp.full_name
      from public.staff_profiles sp
      where sp.id = v_staff_profile_id
    ),
    'Marks submission received',
    'marks-submission-confirmation',
    jsonb_build_object(
      'marks_batch_id', v_batch_id,
      'offering_code', upper(btrim(v_payload->>'course_offering_code')),
      'section_code', upper(btrim(v_payload->>'section_code')),
      'assessment_code', upper(btrim(v_payload->>'assessment_code')),
      'status', v_batch_status,
      'validation_summary', v_validation_summary
    ),
    v_correlation_id,
    v_idempotency_key || ':notification',
    'pending',
    100
  )
  on conflict (
    institution_id,
    channel,
    notification_type,
    idempotency_key
  ) do nothing;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'marks_batch_id', v_batch_id,
      'status', v_batch_status,
      'validation_summary', v_validation_summary,
      'submission_state',
        case
          when v_finalize_requested then 'finalized'
          else 'draft'
        end
    ),
    case
      when v_error_count > 0 then
        jsonb_build_array(
          'The marks batch contains validation errors and cannot be finalized.'
        )
      else
        '[]'::jsonb
    end
  );
exception
  when others then
    return app.exception_rpc_error(
      v_operation,
      v_correlation_id,
      sqlerrm
    );
end;
$function$;

revoke all on function public.rpc_submit_marks_from_form(jsonb)
from public, anon, authenticated;

grant execute on function public.rpc_submit_marks_from_form(jsonb)
to service_role;

comment on function public.rpc_submit_marks_from_form(jsonb) is
  'Service-role-only Google Form marks wrapper: resolves codes, verifies the captured teacher assignment, validates class coverage, submits a versioned batch and optionally finalizes it.';

commit;
