-- Workflow 04 publication repair.
-- PostgreSQL INSERT ... SELECT resolves an uncast string literal as text.
-- ops.notification_outbox.channel uses ops.notification_channel, so an
-- explicit enum cast is required. This definition also retains the valid
-- audit outcome='success' repair.

begin;

create or replace function public.rpc_publish_results(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'results.publish';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_offering_id uuid := nullif(
    p_request#>>'{payload,course_offering_id}',
    ''
  )::uuid;
  v_force boolean :=
    lower(coalesce(p_request#>>'{payload,force_recalculate}', 'false'))
    in ('true', '1', 'yes');
  v_institution_id uuid;
  v_campus_id uuid;
  v_term_id uuid;
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_student_id uuid;
  v_result_count integer := 0;
  v_published_count integer := 0;
  v_enrollment_count integer := 0;
  v_records jsonb := '[]'::jsonb;
  v_academic jsonb;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_result jsonb;
  v_error jsonb;
begin
  if v_offering_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_COURSE_OFFERING_ID_REQUIRED';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  select co.institution_id, co.campus_id, co.term_id
    into v_institution_id, v_campus_id, v_term_id
  from public.course_offerings co
  where co.id = v_offering_id;

  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'RESULT_OFFERING_NOT_FOUND';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  if not app.staff_can_administer_results(
    v_actor_staff_id,
    v_institution_id,
    v_campus_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'course_offering_id', v_offering_id,
      'force_recalculate', v_force
    )
  );

  v_idem := app.begin_idempotency(
    v_institution_id,
    v_operation,
    v_idempotency_key,
    v_hash,
    v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;

  if v_idem->>'state' in ('completed', 'failed') then
    return v_idem->'existing_result';
  end if;

  if not exists (
    select 1
    from public.marks_batches mb
    where mb.offering_id = v_offering_id
      and mb.batch_status = 'approved'
  ) then
    raise exception using errcode = 'P0001', message = 'RESULT_APPROVED_MARKS_REQUIRED';
  end if;

  select count(*)
    into v_enrollment_count
  from public.enrollments e
  where e.course_offering_id = v_offering_id
    and e.enrollment_status <> 'cancelled';

  select count(*)
    into v_published_count
  from public.course_results cr
  where cr.course_offering_id = v_offering_id
    and cr.result_status = 'published';

  if not v_force
     and v_enrollment_count > 0
     and v_published_count = v_enrollment_count then
    v_result := app.rpc_success(
      v_operation,
      v_correlation_id,
      v_idempotency_key,
      jsonb_build_object(
        'course_offering_id', v_offering_id,
        'published_student_count', v_published_count,
        'already_published', true
      )
    );
    perform app.complete_idempotency(v_idem_id, v_result);
    return v_result;
  end if;

  for v_student_id in
    select distinct e.student_id
    from public.enrollments e
    where e.course_offering_id = v_offering_id
      and e.enrollment_status <> 'cancelled'
  loop
    perform app.calculate_course_result(
      v_student_id,
      v_offering_id,
      v_correlation_id
    );

    update public.course_results
    set
      result_status = 'published',
      approved_at = coalesce(
        approved_at,
        timezone('utc', now())
      ),
      published_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where student_id = v_student_id
      and course_offering_id = v_offering_id;

    v_academic := app.recalculate_academic_record(
      v_student_id,
      v_term_id,
      v_correlation_id
    );

    update public.semester_results
    set
      result_status = 'published',
      published_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where student_id = v_student_id
      and term_id = v_term_id;

    v_records := v_records || jsonb_build_array(
      jsonb_build_object(
        'student_id', v_student_id,
        'academic_record', v_academic
      )
    );
    v_result_count := v_result_count + 1;
  end loop;

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
    idempotency_key
  )
  select distinct
    s.institution_id,
    s.campus_id,
    'email'::ops.notification_channel,
    'results.published'::text,
    s.primary_email,
    s.full_name,
    'Academic results published',
    'results-published',
    jsonb_build_object(
      'student_id', s.id,
      'student_number', s.student_number,
      'course_offering_id', v_offering_id,
      'term_id', v_term_id
    ),
    v_correlation_id,
    v_offering_id::text || ':' || s.id::text || ':results-published'
  from public.students s
  join public.enrollments e on e.student_id = s.id
  where e.course_offering_id = v_offering_id
    and e.enrollment_status <> 'cancelled'
    and s.primary_email is not null
  on conflict (
    institution_id,
    channel,
    notification_type,
    idempotency_key
  ) do nothing;

  insert into audit.audit_logs (
    institution_id,
    campus_id,
    actor_auth_user_id,
    actor_staff_profile_id,
    operation,
    entity_type,
    entity_id,
    correlation_id,
    outcome,
    details
  )
  values (
    v_institution_id,
    v_campus_id,
    v_actor_auth_user_id,
    v_actor_staff_id,
    v_operation,
    'course_offering',
    v_offering_id,
    v_correlation_id,
    'success',
    jsonb_build_object(
      'published_student_count', v_result_count,
      'force_recalculate', v_force
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'course_offering_id', v_offering_id,
      'term_id', v_term_id,
      'published_student_count', v_result_count,
      'already_published', false,
      'records', v_records
    )
  );

  perform app.complete_idempotency(v_idem_id, v_result);
  return v_result;
exception when others then
  v_error := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
  if v_idem_id is not null then
    perform app.fail_idempotency(v_idem_id, v_error);
  end if;
  return v_error;
end;
$function$;

commit;
