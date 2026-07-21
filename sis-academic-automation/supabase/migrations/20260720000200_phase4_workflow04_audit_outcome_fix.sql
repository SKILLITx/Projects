-- Workflow 04 repair:
-- audit.audit_logs accepts success, failure, denied or warning.
-- The original Workflow 04 RPCs attempted to write outcome='completed',
-- causing the whole transaction to roll back with SYSTEM_UNEXPECTED.

begin;

create or replace function public.rpc_decide_marks_batch(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.batch.decide';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_batch_id uuid := nullif(p_request#>>'{payload,marks_batch_id}', '')::uuid;
  v_decision public.approval_decision :=
    nullif(p_request#>>'{payload,decision}', '')::public.approval_decision;
  v_reason text := nullif(btrim(coalesce(p_request#>>'{payload,reason}', '')), '');
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_batch public.marks_batches%rowtype;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_result jsonb;
  v_error jsonb;
  v_student_id uuid;
  v_result_count integer := 0;
  v_notification_type text;
begin
  if v_batch_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_MARKS_BATCH_ID_REQUIRED';
  end if;

  if v_decision not in ('approved', 'rejected', 'returned') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_DECISION_INVALID';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  select *
    into v_batch
  from public.marks_batches mb
  where mb.id = v_batch_id
  for update;

  if v_batch.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FOUND';
  end if;

  if not app.staff_can_administer_results(
    v_actor_staff_id,
    v_batch.institution_id,
    v_batch.campus_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'marks_batch_id', v_batch_id,
      'decision', v_decision,
      'reason', v_reason
    )
  );

  v_idem := app.begin_idempotency(
    v_batch.institution_id,
    v_operation,
    v_idempotency_key,
    v_hash,
    v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;

  if v_idem->>'state' in ('completed', 'failed') then
    return v_idem->'existing_result';
  end if;

  if v_batch.batch_status <> 'finalized' then
    if (
      v_decision = 'approved'
      and v_batch.batch_status = 'approved'
    ) or (
      v_decision in ('rejected', 'returned')
      and v_batch.batch_status = 'rejected'
    ) then
      v_result := app.rpc_success(
        v_operation,
        v_correlation_id,
        v_idempotency_key,
        jsonb_build_object(
          'marks_batch_id', v_batch.id,
          'decision', v_decision,
          'status', v_batch.batch_status,
          'already_decided', true
        )
      );
      perform app.complete_idempotency(v_idem_id, v_result);
      return v_result;
    end if;

    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FINALIZED';
  end if;

  insert into public.marks_approval_history (
    institution_id,
    marks_batch_id,
    decision,
    reason,
    decided_by,
    correlation_id
  )
  values (
    v_batch.institution_id,
    v_batch.id,
    v_decision,
    v_reason,
    v_actor_auth_user_id,
    v_correlation_id
  );

  update public.marks_batches
  set
    batch_status = case
      when v_decision = 'approved'
        then 'approved'::public.marks_batch_status
      else 'rejected'::public.marks_batch_status
    end,
    approved_at = case
      when v_decision = 'approved'
        then timezone('utc', now())
      else null
    end,
    approved_by = case
      when v_decision = 'approved'
        then v_actor_auth_user_id
      else null
    end,
    updated_at = timezone('utc', now())
  where id = v_batch.id;

  if v_decision = 'approved' then
    for v_student_id in
      select distinct sm.student_id
      from public.student_marks sm
      where sm.marks_batch_id = v_batch.id
    loop
      perform app.calculate_course_result(
        v_student_id,
        v_batch.offering_id,
        v_correlation_id
      );
      v_result_count := v_result_count + 1;
    end loop;
  end if;

  v_notification_type := case v_decision
    when 'approved' then 'marks.batch.approved'
    when 'returned' then 'marks.batch.returned'
    else 'marks.batch.rejected'
  end;

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
  select
    v_batch.institution_id,
    v_batch.campus_id,
    'email',
    v_notification_type,
    sp.email,
    sp.full_name,
    case v_decision
      when 'approved' then 'Marks batch approved'
      when 'returned' then 'Marks batch returned for correction'
      else 'Marks batch rejected'
    end,
    replace(v_notification_type, '.', '-'),
    jsonb_build_object(
      'marks_batch_id', v_batch.id,
      'decision', v_decision,
      'reason', v_reason,
      'course_offering_id', v_batch.offering_id,
      'section_id', v_batch.section_id
    ),
    v_correlation_id,
    v_batch.id::text || ':' || v_decision::text
  from public.staff_profiles sp
  where sp.id = v_batch.submitted_by_staff_profile_id
    and sp.status = 'active'
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
    v_batch.institution_id,
    v_batch.campus_id,
    v_actor_auth_user_id,
    v_actor_staff_id,
    v_operation,
    'marks_batch',
    v_batch.id,
    v_correlation_id,
    'success',
    jsonb_build_object(
      'decision', v_decision,
      'reason', v_reason,
      'calculated_student_count', v_result_count
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'marks_batch_id', v_batch.id,
      'course_offering_id', v_batch.offering_id,
      'decision', v_decision,
      'status', case
        when v_decision = 'approved' then 'approved'
        else 'rejected'
      end,
      'calculated_student_count', v_result_count
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
    'email',
    'marks.correction.requested',
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

create or replace function public.rpc_decide_mark_correction(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.correction.decide';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_correction_id uuid := nullif(
    p_request#>>'{payload,correction_request_id}',
    ''
  )::uuid;
  v_decision public.approval_decision :=
    nullif(p_request#>>'{payload,decision}', '')::public.approval_decision;
  v_reason text := nullif(btrim(coalesce(p_request#>>'{payload,reason}', '')), '');
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_correction public.mark_correction_requests%rowtype;
  v_mark public.student_marks%rowtype;
  v_batch public.marks_batches%rowtype;
  v_assessment public.assessments%rowtype;
  v_requester_email text;
  v_requester_name text;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_result jsonb;
  v_error jsonb;
begin
  if v_correction_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CORRECTION_REQUEST_ID_REQUIRED';
  end if;

  if v_decision not in ('approved', 'rejected') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_DECISION_INVALID';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  select *
    into v_correction
  from public.mark_correction_requests mcr
  where mcr.id = v_correction_id
  for update;

  if v_correction.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_NOT_FOUND';
  end if;

  if not app.staff_can_administer_results(
    v_actor_staff_id,
    v_correction.institution_id,
    v_correction.campus_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'correction_request_id', v_correction.id,
      'decision', v_decision,
      'reason', v_reason
    )
  );

  v_idem := app.begin_idempotency(
    v_correction.institution_id,
    v_operation,
    v_idempotency_key,
    v_hash,
    v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;

  if v_idem->>'state' in ('completed', 'failed') then
    return v_idem->'existing_result';
  end if;

  if v_correction.correction_status <> 'requested' then
    v_result := app.rpc_success(
      v_operation,
      v_correlation_id,
      v_idempotency_key,
      jsonb_build_object(
        'correction_request_id', v_correction.id,
        'status', v_correction.correction_status,
        'already_decided', true
      )
    );
    perform app.complete_idempotency(v_idem_id, v_result);
    return v_result;
  end if;

  select sm.*
    into v_mark
  from public.student_marks sm
  where sm.id = v_correction.student_mark_id
  for update;

  select mb.*
    into v_batch
  from public.marks_batches mb
  where mb.id = v_correction.marks_batch_id;

  select a.*
    into v_assessment
  from public.assessments a
  where a.id = v_mark.assessment_id;

  if v_mark.id is null
     or v_batch.id is null
     or v_assessment.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_SOURCE_RECORD_MISSING';
  end if;

  if v_decision = 'approved' then
    if v_correction.proposed_marks is null
       or v_correction.proposed_marks < 0
       or v_correction.proposed_marks > v_assessment.maximum_marks then
      raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_VALUE_OUT_OF_RANGE';
    end if;

    update public.student_marks
    set
      marks_obtained = v_correction.proposed_marks,
      is_absent = false,
      is_missing = false,
      remarks = concat_ws(
        ' | ',
        nullif(remarks, ''),
        'Corrected under request ' || v_correction.id::text
      ),
      updated_at = timezone('utc', now())
    where id = v_mark.id;

    update public.mark_correction_requests
    set
      correction_status = 'applied',
      decision_reason = v_reason,
      decided_by = v_actor_auth_user_id,
      decided_at = timezone('utc', now()),
      applied_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where id = v_correction.id;

    perform app.calculate_course_result(
      v_mark.student_id,
      v_batch.offering_id,
      v_correlation_id
    );
  else
    update public.mark_correction_requests
    set
      correction_status = 'rejected',
      decision_reason = v_reason,
      decided_by = v_actor_auth_user_id,
      decided_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where id = v_correction.id;
  end if;

  select sp.email, sp.full_name
    into v_requester_email, v_requester_name
  from public.staff_profiles sp
  where sp.id = v_correction.requested_by_staff_profile_id;

  if v_requester_email is not null then
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
    values (
      v_correction.institution_id,
      v_correction.campus_id,
      'email',
      case
        when v_decision = 'approved'
          then 'marks.correction.applied'
        else 'marks.correction.rejected'
      end,
      v_requester_email,
      v_requester_name,
      case
        when v_decision = 'approved'
          then 'Mark correction approved and applied'
        else 'Mark correction request rejected'
      end,
      case
        when v_decision = 'approved'
          then 'marks-correction-applied'
        else 'marks-correction-rejected'
      end,
      jsonb_build_object(
        'correction_request_id', v_correction.id,
        'marks_batch_id', v_batch.id,
        'student_mark_id', v_mark.id,
        'decision', v_decision,
        'reason', v_reason,
        'applied_marks', case
          when v_decision = 'approved'
            then v_correction.proposed_marks
          else null
        end
      ),
      v_correlation_id,
      v_correction.id::text || ':' || v_decision::text
    )
    on conflict (
      institution_id,
      channel,
      notification_type,
      idempotency_key
    ) do nothing;
  end if;

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
    v_correction.institution_id,
    v_correction.campus_id,
    v_actor_auth_user_id,
    v_actor_staff_id,
    v_operation,
    'mark_correction_request',
    v_correction.id,
    v_correlation_id,
    'success',
    jsonb_build_object(
      'decision', v_decision,
      'reason', v_reason,
      'student_mark_id', v_mark.id,
      'proposed_marks', v_correction.proposed_marks
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'correction_request_id', v_correction.id,
      'status', case
        when v_decision = 'approved' then 'applied'
        else 'rejected'
      end,
      'course_offering_id', v_batch.offering_id,
      'result_republication_required', v_decision = 'approved'
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
    'email',
    'results.published',
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
