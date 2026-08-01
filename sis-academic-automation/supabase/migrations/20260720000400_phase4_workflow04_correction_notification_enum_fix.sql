-- Workflow 04 mark-correction request repair.
-- The notification outbox channel column is ops.notification_channel.
-- INSERT ... SELECT requires an explicit enum cast.
-- This definition also preserves the valid audit outcome='success'.

begin;

create or replace function public.rpc_request_mark_correction(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.correction.request';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_institution_id uuid := nullif(p_request->>'institution_id', '')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id', '')::uuid;
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_batch_id uuid := nullif(p_request#>>'{payload,marks_batch_id}', '')::uuid;
  v_student_mark_id uuid := nullif(p_request#>>'{payload,student_mark_id}', '')::uuid;
  v_reason text := btrim(coalesce(p_request#>>'{payload,reason}', ''));
  v_proposed_marks numeric := nullif(p_request#>>'{payload,proposed_marks}', '')::numeric;
  v_current_marks numeric := nullif(p_request#>>'{payload,current_marks}', '')::numeric;
  v_student_number text := upper(btrim(coalesce(
    p_request#>>'{payload,student_number}',
    ''
  )));
  v_assessment_code text := upper(btrim(coalesce(
    p_request#>>'{payload,assessment_code}',
    ''
  )));
  v_evidence_url text := nullif(btrim(coalesce(
    p_request#>>'{payload,evidence_drive_url}',
    ''
  )), '');
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_batch public.marks_batches%rowtype;
  v_mark public.student_marks%rowtype;
  v_assessment public.assessments%rowtype;
  v_actual_student_number text;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_correction_id uuid;
  v_result jsonb;
  v_error jsonb;
begin
  if v_institution_id is null
     or v_campus_id is null
     or v_batch_id is null
     or v_student_mark_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CORRECTION_SCOPE_REQUIRED';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  if length(v_reason) < 10 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CORRECTION_REASON_REQUIRED';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  select *
    into v_batch
  from public.marks_batches mb
  where mb.id = v_batch_id
    and mb.institution_id = v_institution_id
    and mb.campus_id = v_campus_id;

  if v_batch.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FOUND';
  end if;

  if v_batch.batch_status not in ('finalized', 'approved') then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_BATCH_STATE_INVALID';
  end if;

  select sm.*
    into v_mark
  from public.student_marks sm
  where sm.id = v_student_mark_id
    and sm.marks_batch_id = v_batch.id
    and sm.institution_id = v_institution_id;

  if v_mark.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_STUDENT_MARK_NOT_FOUND';
  end if;

  select a.*
    into v_assessment
  from public.assessments a
  where a.id = v_mark.assessment_id
    and a.institution_id = v_institution_id;

  select s.student_number
    into v_actual_student_number
  from public.students s
  where s.id = v_mark.student_id;

  if v_student_number <> ''
     and upper(v_actual_student_number) <> v_student_number then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_STUDENT_MISMATCH';
  end if;

  if v_assessment_code <> ''
     and upper(v_assessment.code) <> v_assessment_code then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_ASSESSMENT_MISMATCH';
  end if;

  if v_current_marks is not null
     and v_mark.marks_obtained is distinct from v_current_marks then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_CURRENT_VALUE_CHANGED';
  end if;

  if v_proposed_marks is null
     or v_proposed_marks < 0
     or v_proposed_marks > v_assessment.maximum_marks then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_VALUE_OUT_OF_RANGE';
  end if;

  if not (
    app.staff_can_administer_results(
      v_actor_staff_id,
      v_institution_id,
      v_campus_id
    )
    or app.staff_is_teacher_for_results_section(
      v_actor_staff_id,
      v_institution_id,
      v_campus_id,
      v_batch.section_id
    )
    or v_batch.submitted_by_staff_profile_id = v_actor_staff_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'marks_batch_id', v_batch_id,
      'student_mark_id', v_student_mark_id,
      'proposed_marks', v_proposed_marks,
      'reason', v_reason,
      'evidence_url', v_evidence_url
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

  insert into public.mark_correction_requests (
    institution_id,
    campus_id,
    marks_batch_id,
    student_mark_id,
    requested_by_staff_profile_id,
    requested_by_student_id,
    reason,
    proposed_marks,
    correction_status,
    correlation_id,
    idempotency_key,
    evidence_url
  )
  values (
    v_institution_id,
    v_campus_id,
    v_batch.id,
    v_mark.id,
    v_actor_staff_id,
    null,
    v_reason,
    v_proposed_marks,
    'requested',
    v_correlation_id,
    v_idempotency_key,
    v_evidence_url
  )
  on conflict (institution_id, idempotency_key)
  do update set updated_at = public.mark_correction_requests.updated_at
  returning id into v_correction_id;

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
    v_institution_id,
    v_campus_id,
    'email'::ops.notification_channel,
    'marks.correction.requested'::text,
    sp.email,
    sp.full_name,
    'Mark correction request awaiting review',
    'marks-correction-requested',
    jsonb_build_object(
      'correction_request_id', v_correction_id,
      'marks_batch_id', v_batch.id,
      'student_mark_id', v_mark.id,
      'student_number', v_actual_student_number,
      'assessment_code', v_assessment.code,
      'proposed_marks', v_proposed_marks,
      'reason', v_reason
    ),
    v_correlation_id,
    v_correction_id::text || ':' || sp.id::text || ':requested'
  from public.staff_profiles sp
  join public.role_assignments ra on ra.staff_profile_id = sp.id
  left join public.campus_assignments ca
    on ca.role_assignment_id = ra.id
   and ca.institution_id = ra.institution_id
  where sp.status = 'active'
    and ra.status = 'active'
    and ra.valid_from <= timezone('utc', now())
    and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    and (
      (
        ra.role = 'super_administrator'
        and ra.institution_id is null
      )
      or (
        ra.role = 'registrar_admin'
        and ra.institution_id = v_institution_id
      )
      or (
        ra.role = 'campus_administrator'
        and ra.institution_id = v_institution_id
        and ca.campus_id = v_campus_id
        and ca.status = 'active'
        and ca.valid_from <= timezone('utc', now())
        and (ca.valid_to is null or ca.valid_to > timezone('utc', now()))
      )
    )
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
    'mark_correction_request',
    v_correction_id,
    v_correlation_id,
    'success',
    jsonb_build_object(
      'marks_batch_id', v_batch.id,
      'student_mark_id', v_mark.id,
      'proposed_marks', v_proposed_marks,
      'evidence_url', v_evidence_url
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'correction_request_id', v_correction_id,
      'status', 'requested',
      'marks_batch_id', v_batch.id,
      'student_mark_id', v_mark.id
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
