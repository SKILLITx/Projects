-- Phase 2 accelerated completion, migration 7:
-- stable public JSON RPC wrappers used by n8n and the authenticated staff portal.

begin;

create or replace function app.request_hash(p_request jsonb)
returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $function$
  select encode(extensions.digest(convert_to(coalesce(p_request, '{}'::jsonb)::text, 'utf8'), 'sha256'), 'hex');
$function$;

create or replace function app.is_service_request()
returns boolean
language sql
stable
security invoker
set search_path = pg_catalog
as $function$
  select coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
$function$;

create or replace function app.rpc_success(
  p_operation text,
  p_correlation_id uuid,
  p_idempotency_key text,
  p_data jsonb,
  p_warnings jsonb default '[]'::jsonb
)
returns jsonb
language sql
immutable
security invoker
set search_path = pg_catalog
as $function$
  select jsonb_build_object(
    'success', true,
    'operation', p_operation,
    'correlation_id', p_correlation_id,
    'idempotency_key', p_idempotency_key,
    'data', coalesce(p_data, '{}'::jsonb),
    'warnings', coalesce(p_warnings, '[]'::jsonb)
  );
$function$;

create or replace function app.rpc_error(
  p_operation text,
  p_correlation_id uuid,
  p_code text,
  p_message text,
  p_retryable boolean default false
)
returns jsonb
language sql
immutable
security invoker
set search_path = pg_catalog
as $function$
  select jsonb_build_object(
    'success', false,
    'operation', p_operation,
    'correlation_id', p_correlation_id,
    'error', jsonb_build_object(
      'code', p_code,
      'message', p_message,
      'retryable', p_retryable
    )
  );
$function$;

create or replace function app.exception_rpc_error(
  p_operation text,
  p_correlation_id uuid,
  p_sqlerrm text
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = pg_catalog
as $function$
declare
  v_code text;
  v_message text;
  v_retryable boolean := false;
begin
  if coalesce(p_sqlerrm,'') ~ '^[A-Z][A-Z0-9_]{2,79}$' then
    v_code := p_sqlerrm;
  else
    v_code := 'SYSTEM_UNEXPECTED';
  end if;

  v_message := case
    when v_code like 'AUTH_%' then 'You are not authorized to perform this operation.'
    when v_code like 'VALIDATION_%' then 'The submitted information is invalid.'
    when v_code like 'CONFIG_%' then 'Required institutional configuration is unavailable.'
    when v_code like 'STUDENT_%' then 'The student record could not be processed.'
    when v_code like 'ENROLLMENT_%' then 'The enrollment request could not be completed.'
    when v_code like 'MARKS_%' then 'The marks operation could not be completed.'
    when v_code like 'RESULT_%' then 'The result operation could not be completed.'
    when v_code like 'TRANSCRIPT_%' then 'The transcript operation could not be completed.'
    when v_code like 'REPORT_%' then 'The report operation could not be completed.'
    when v_code like 'NOTIFICATION_%' then 'The notification operation could not be completed.'
    when v_code like 'INCIDENT_%' then 'The incident could not be recorded.'
    else 'The operation could not be completed.'
  end;

  v_retryable := v_code in (
    'SYSTEM_TEMPORARY_FAILURE',
    'NOTIFICATION_TEMPORARY_FAILURE',
    'REPORT_TEMPORARY_FAILURE'
  );

  return app.rpc_error(p_operation, p_correlation_id, v_code, v_message, v_retryable);
end;
$function$;

create or replace function app.begin_idempotency(
  p_institution_id uuid,
  p_operation text,
  p_idempotency_key text,
  p_request_hash text,
  p_correlation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_record ops.idempotency_records%rowtype;
begin
  if p_institution_id is null or btrim(coalesce(p_operation,'')) = ''
     or btrim(coalesce(p_idempotency_key,'')) = ''
     or p_request_hash !~ '^[A-Fa-f0-9]{64}$'
     or p_correlation_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  insert into ops.idempotency_records (
    institution_id, operation, idempotency_key, request_hash, correlation_id,
    state, locked_until
  )
  values (
    p_institution_id, p_operation, p_idempotency_key, p_request_hash,
    p_correlation_id, 'processing', timezone('utc', now()) + interval '5 minutes'
  )
  on conflict (institution_id, operation, idempotency_key) do nothing;

  select *
    into v_record
  from ops.idempotency_records
  where institution_id = p_institution_id
    and operation = p_operation
    and idempotency_key = p_idempotency_key
  for update;

  if v_record.request_hash <> p_request_hash then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_KEY_REUSED';
  end if;

  return jsonb_build_object(
    'record_id', v_record.id,
    'state', v_record.state,
    'existing_result', case
      when v_record.state = 'completed' then v_record.result_payload
      when v_record.state = 'failed' then v_record.error_payload
      else null
    end
  );
end;
$function$;

create or replace function app.complete_idempotency(
  p_record_id uuid,
  p_result jsonb
)
returns void
language sql
security definer
set search_path = ''
as $function$
  update ops.idempotency_records
  set state = 'completed',
      result_payload = p_result,
      error_payload = null,
      locked_until = null,
      updated_at = timezone('utc', now())
  where id = p_record_id;
$function$;

create or replace function app.fail_idempotency(
  p_record_id uuid,
  p_error jsonb
)
returns void
language sql
security definer
set search_path = ''
as $function$
  update ops.idempotency_records
  set state = 'failed',
      error_payload = p_error,
      locked_until = null,
      updated_at = timezone('utc', now())
  where id = p_record_id;
$function$;

create or replace function app.require_service()
returns void
language plpgsql
stable
security invoker
set search_path = pg_catalog
as $function$
begin
  if not app.is_service_request() then
    raise exception using errcode = 'P0001', message = 'AUTH_SERVICE_ROLE_REQUIRED';
  end if;
end;
$function$;

revoke all on function app.request_hash(jsonb) from public, anon, authenticated;
revoke all on function app.is_service_request() from public, anon, authenticated;
revoke all on function app.rpc_success(text, uuid, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function app.rpc_error(text, uuid, text, text, boolean) from public, anon, authenticated;
revoke all on function app.exception_rpc_error(text, uuid, text) from public, anon, authenticated;
revoke all on function app.begin_idempotency(uuid, text, text, text, uuid) from public, anon, authenticated;
revoke all on function app.complete_idempotency(uuid, jsonb) from public, anon, authenticated;
revoke all on function app.fail_idempotency(uuid, jsonb) from public, anon, authenticated;
revoke all on function app.require_service() from public, anon, authenticated;

grant execute on function app.request_hash(jsonb) to service_role;
grant execute on function app.is_service_request() to authenticated, service_role;
grant execute on function app.rpc_success(text, uuid, text, jsonb, jsonb) to authenticated, service_role;
grant execute on function app.rpc_error(text, uuid, text, text, boolean) to authenticated, service_role;
grant execute on function app.exception_rpc_error(text, uuid, text) to authenticated, service_role;
grant execute on function app.begin_idempotency(uuid, text, text, text, uuid) to service_role;
grant execute on function app.complete_idempotency(uuid, jsonb) to service_role;
grant execute on function app.fail_idempotency(uuid, jsonb) to service_role;
grant execute on function app.require_service() to service_role;

create or replace function public.rpc_submit_student_profile(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'student.profile.submit';
  v_correlation_id uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_idempotency_key text;
  v_payload jsonb;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_existing jsonb;
  v_student_id uuid;
  v_request_id uuid;
  v_program_id uuid;
  v_academic_year_id uuid;
  v_start_term_id uuid;
  v_student_number text;
  v_full_name text;
  v_email text;
  v_status public.student_status;
  v_document jsonb;
  v_requirement_id uuid;
  v_result jsonb;
begin
  perform app.require_service();

  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_OBJECT_REQUIRED';
  end if;

  v_correlation_id := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id := nullif(p_request->>'campus_id','')::uuid;
  v_idempotency_key := p_request->>'idempotency_key';
  v_payload := coalesce(p_request->'payload', '{}'::jsonb);
  v_hash := app.request_hash(p_request);

  if v_institution_id is null or v_campus_id is null or btrim(coalesce(v_idempotency_key,'')) = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  if not exists (
    select 1 from public.campuses c
    where c.id = v_campus_id and c.institution_id = v_institution_id and c.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'CONFIG_CAMPUS_NOT_FOUND';
  end if;

  v_idem := app.begin_idempotency(
    v_institution_id, v_operation, v_idempotency_key, v_hash, v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;
  v_existing := v_idem->'existing_result';

  if v_existing is not null and v_existing <> 'null'::jsonb then
    return v_existing;
  end if;

  v_student_number := btrim(coalesce(v_payload->>'student_number',''));
  v_full_name := btrim(coalesce(v_payload->>'full_name',''));
  v_email := nullif(lower(btrim(coalesce(v_payload->>'primary_email',''))), '');
  v_program_id := nullif(v_payload->>'program_id','')::uuid;
  v_academic_year_id := nullif(v_payload->>'academic_year_id','')::uuid;
  v_start_term_id := nullif(v_payload->>'start_term_id','')::uuid;
  v_status := coalesce(nullif(v_payload->>'status','')::public.student_status, 'active');

  if v_student_number = '' or v_full_name = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_STUDENT_REQUIRED_FIELDS';
  end if;

  if v_email is not null and position('@' in v_email) <= 1 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_EMAIL_INVALID';
  end if;

  select s.id into v_student_id
  from public.students s
  where s.institution_id = v_institution_id
    and upper(s.student_number) = upper(v_student_number)
  for update;

  if v_student_id is null then
    insert into public.students (
      institution_id, campus_id, student_number, full_name, date_of_birth,
      cnic_hash, primary_email, status, admitted_on, metadata
    )
    values (
      v_institution_id,
      v_campus_id,
      v_student_number,
      v_full_name,
      nullif(v_payload->>'date_of_birth','')::date,
      nullif(v_payload->>'cnic_hash',''),
      v_email,
      v_status,
      coalesce(nullif(v_payload->>'admitted_on','')::date, current_date),
      coalesce(v_payload->'metadata', '{}'::jsonb)
    )
    returning id into v_student_id;
  else
    update public.students
    set campus_id = v_campus_id,
        full_name = v_full_name,
        date_of_birth = coalesce(nullif(v_payload->>'date_of_birth','')::date, date_of_birth),
        cnic_hash = coalesce(nullif(v_payload->>'cnic_hash',''), cnic_hash),
        primary_email = coalesce(v_email, primary_email),
        status = v_status,
        metadata = metadata || coalesce(v_payload->'metadata', '{}'::jsonb),
        updated_at = timezone('utc', now())
    where id = v_student_id;
  end if;

  insert into public.student_profile_requests (
    institution_id, campus_id, student_id, operation, correlation_id,
    idempotency_key, source_submission_id, request_payload, request_hash,
    request_status
  )
  values (
    v_institution_id,
    v_campus_id,
    v_student_id,
    case when exists (
      select 1 from public.student_profile_requests spr
      where spr.student_id = v_student_id
    ) then 'student.profile.update' else 'student.profile.create' end,
    v_correlation_id,
    v_idempotency_key,
    p_request#>>'{source,source_submission_id}',
    p_request,
    v_hash,
    'accepted'
  )
  returning id into v_request_id;

  if v_program_id is not null then
    if v_academic_year_id is null then
      select ay.id into v_academic_year_id
      from public.academic_years ay
      where ay.institution_id = v_institution_id and ay.status = 'active'
      order by ay.starts_on desc
      limit 1;
    end if;

    if v_academic_year_id is null or not exists (
      select 1 from public.programs p
      where p.id = v_program_id and p.institution_id = v_institution_id and p.status = 'active'
    ) then
      raise exception using errcode = 'P0001', message = 'CONFIG_PROGRAM_OR_YEAR_NOT_FOUND';
    end if;

    insert into public.student_program_registrations (
      institution_id, campus_id, student_id, program_id, academic_year_id,
      start_term_id, cohort_code, registration_status, current_term_sequence
    )
    values (
      v_institution_id, v_campus_id, v_student_id, v_program_id, v_academic_year_id,
      v_start_term_id, nullif(v_payload->>'cohort_code',''), 'active',
      coalesce(nullif(v_payload->>'current_term_sequence','')::integer, 1)
    )
    on conflict (student_id, program_id)
      where registration_status in ('pending','active')
    do update set
      campus_id = excluded.campus_id,
      academic_year_id = excluded.academic_year_id,
      start_term_id = coalesce(excluded.start_term_id, public.student_program_registrations.start_term_id),
      cohort_code = coalesce(excluded.cohort_code, public.student_program_registrations.cohort_code),
      registration_status = 'active',
      updated_at = timezone('utc', now());
  end if;

  if jsonb_typeof(v_payload->'documents') = 'array' then
    for v_document in select value from jsonb_array_elements(v_payload->'documents')
    loop
      v_requirement_id := nullif(v_document->>'requirement_id','')::uuid;
      if v_requirement_id is null or not exists (
        select 1 from public.document_requirements dr
        where dr.id = v_requirement_id and dr.institution_id = v_institution_id
      ) then
        raise exception using errcode = 'P0001', message = 'VALIDATION_DOCUMENT_REQUIREMENT_INVALID';
      end if;

      insert into public.student_documents (
        institution_id, student_id, requirement_id, file_name, storage_provider,
        storage_object_id, checksum_sha256, document_status, expires_on
      )
      values (
        v_institution_id,
        v_student_id,
        v_requirement_id,
        nullif(v_document->>'file_name',''),
        nullif(v_document->>'storage_provider',''),
        nullif(v_document->>'storage_object_id',''),
        nullif(v_document->>'checksum_sha256',''),
        coalesce(nullif(v_document->>'document_status','')::public.student_document_status, 'submitted'),
        nullif(v_document->>'expires_on','')::date
      );
    end loop;
  end if;

  if v_email is not null then
    insert into ops.notification_outbox (
      institution_id, campus_id, channel, notification_type, recipient_address,
      recipient_name, subject, template_code, payload, correlation_id,
      idempotency_key
    )
    values (
      v_institution_id, v_campus_id, 'email', 'student.profile.acknowledged',
      v_email, v_full_name, 'Student profile received', 'student-profile-ack',
      jsonb_build_object('student_id', v_student_id, 'student_number', v_student_number),
      v_correlation_id, v_idempotency_key || ':profile-ack'
    )
    on conflict (institution_id, channel, notification_type, idempotency_key) do nothing;
  end if;

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'student_id', v_student_id,
      'student_number', v_student_number,
      'profile_request_id', v_request_id,
      'status', v_status
    )
  );

  update public.student_profile_requests
  set request_status = 'completed', result_payload = v_result
  where id = v_request_id;

  perform app.complete_idempotency(v_idem_id, v_result);

  insert into audit.audit_logs (
    institution_id, campus_id, operation, entity_type, entity_id,
    correlation_id, outcome, details
  )
  values (
    v_institution_id, v_campus_id, v_operation, 'student', v_student_id,
    v_correlation_id, 'success', jsonb_build_object('student_number', v_student_number)
  );

  return v_result;
exception
  when others then
    v_result := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
    if v_idem_id is not null then
      perform app.fail_idempotency(v_idem_id, v_result);
    end if;
    return v_result;
end;
$function$;

create or replace function public.rpc_submit_enrollment_request(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'enrollment.submit';
  v_correlation_id uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_idempotency_key text;
  v_payload jsonb;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_existing jsonb;
  v_student_id uuid;
  v_period_id uuid;
  v_term_id uuid;
  v_registration_id uuid;
  v_request_id uuid;
  v_item jsonb;
  v_item_id uuid;
  v_offering_id uuid;
  v_preferred_section_id uuid;
  v_selected_section_id uuid;
  v_course_id uuid;
  v_course_load numeric(6,2);
  v_current_load numeric(8,2);
  v_max_load numeric(6,2);
  v_full_behavior public.full_section_behavior;
  v_allow_fallback boolean;
  v_requires_documents boolean;
  v_missing_documents integer;
  v_missing_prerequisites integer;
  v_outcome public.enrollment_outcome;
  v_decision_code text;
  v_enrollment_id uuid;
  v_waitlist_id uuid;
  v_results jsonb := '[]'::jsonb;
  v_overall public.enrollment_outcome := 'enrolled';
  v_result jsonb;
  v_recipient_email text;
  v_position bigint;
begin
  perform app.require_service();

  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_OBJECT_REQUIRED';
  end if;

  v_correlation_id := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id := nullif(p_request->>'campus_id','')::uuid;
  v_idempotency_key := p_request->>'idempotency_key';
  v_payload := coalesce(p_request->'payload', '{}'::jsonb);
  v_hash := app.request_hash(p_request);
  v_student_id := nullif(v_payload->>'student_id','')::uuid;
  v_period_id := nullif(v_payload->>'enrollment_period_id','')::uuid;

  if v_institution_id is null or v_campus_id is null or v_student_id is null
     or v_period_id is null or btrim(coalesce(v_idempotency_key,'')) = ''
     or jsonb_typeof(v_payload->'items') <> 'array'
     or jsonb_array_length(v_payload->'items') = 0 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  select ep.term_id
    into v_term_id
  from public.enrollment_periods ep
  where ep.id = v_period_id
    and ep.institution_id = v_institution_id
    and (ep.campus_id is null or ep.campus_id = v_campus_id)
    and ep.status = 'active'
    and timezone('utc', now()) between ep.opens_at and ep.closes_at;

  if v_term_id is null then
    raise exception using errcode = 'P0001', message = 'ENROLLMENT_PERIOD_CLOSED';
  end if;

  select spr.id
    into v_registration_id
  from public.student_program_registrations spr
  join public.students s on s.id = spr.student_id
  where spr.student_id = v_student_id
    and spr.institution_id = v_institution_id
    and spr.campus_id = v_campus_id
    and spr.registration_status = 'active'
    and s.status = 'active'
  order by spr.created_at desc
  limit 1;

  if v_registration_id is null then
    raise exception using errcode = 'P0001', message = 'STUDENT_NOT_ACTIVE';
  end if;

  v_idem := app.begin_idempotency(
    v_institution_id, v_operation, v_idempotency_key, v_hash, v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;
  v_existing := v_idem->'existing_result';

  if v_existing is not null and v_existing <> 'null'::jsonb then
    return v_existing;
  end if;

  insert into public.enrollment_requests (
    institution_id, campus_id, student_id, enrollment_period_id, term_id,
    program_registration_id, correlation_id, idempotency_key,
    source_submission_id, request_payload, request_hash, request_status
  )
  values (
    v_institution_id, v_campus_id, v_student_id, v_period_id, v_term_id,
    v_registration_id, v_correlation_id, v_idempotency_key,
    p_request#>>'{source,source_submission_id}', p_request, v_hash, 'validating'
  )
  returning id into v_request_id;

  for v_item in select value from jsonb_array_elements(v_payload->'items')
  loop
    v_offering_id := nullif(v_item->>'course_offering_id','')::uuid;
    v_preferred_section_id := nullif(v_item->>'preferred_section_id','')::uuid;
    v_selected_section_id := null;
    v_enrollment_id := null;
    v_waitlist_id := null;
    v_outcome := null;
    v_decision_code := null;

    select
      co.course_id,
      case when c.course_kind = 'course' then c.credit_hours else c.subject_load end,
      ep.maximum_load,
      ep.full_section_behavior,
      ep.allow_section_fallback,
      ep.requires_verified_documents
    into
      v_course_id,
      v_course_load,
      v_max_load,
      v_full_behavior,
      v_allow_fallback,
      v_requires_documents
    from public.course_offerings co
    join public.courses c on c.id = co.course_id
    join public.student_program_registrations spr on spr.id = v_registration_id
    join public.enrollment_policies ep on ep.id = co.enrollment_policy_id
    where co.id = v_offering_id
      and co.institution_id = v_institution_id
      and co.campus_id = v_campus_id
      and co.term_id = v_term_id
      and co.status = 'open'
      and (co.program_id is null or co.program_id = spr.program_id);

    if v_course_id is null then
      v_outcome := 'rejected';
      v_decision_code := 'ENROLLMENT_OFFERING_NOT_AVAILABLE';
    end if;

    insert into public.enrollment_request_items (
      institution_id, enrollment_request_id, course_offering_id,
      preferred_section_id, preference_order, requested_load
    )
    values (
      v_institution_id, v_request_id, v_offering_id, v_preferred_section_id,
      coalesce(nullif(v_item->>'preference_order','')::integer, 1),
      coalesce(v_course_load, 1)
    )
    returning id into v_item_id;

    if v_outcome is null and exists (
      select 1 from public.enrollments e
      where e.student_id = v_student_id
        and e.course_offering_id = v_offering_id
        and e.enrollment_status in ('active','completed','failed','incomplete','audit')
    ) then
      v_outcome := 'rejected';
      v_decision_code := 'ENROLLMENT_DUPLICATE';
    end if;

    if v_outcome is null and v_requires_documents then
      select count(*)::integer
        into v_missing_documents
      from public.document_requirements dr
      join public.student_program_registrations spr on spr.id = v_registration_id
      where dr.institution_id = v_institution_id
        and dr.status = 'active'
        and dr.required_for_enrollment
        and (dr.program_id is null or dr.program_id = spr.program_id)
        and not exists (
          select 1
          from public.student_documents sd
          where sd.student_id = v_student_id
            and sd.requirement_id = dr.id
            and sd.document_status = 'verified'
            and (sd.expires_on is null or sd.expires_on >= current_date)
        );

      if v_missing_documents > 0 then
        v_outcome := 'rejected';
        v_decision_code := 'ENROLLMENT_REQUIRED_DOCUMENT_MISSING';
      end if;
    end if;

    if v_outcome is null then
      select count(*)::integer
        into v_missing_prerequisites
      from public.course_prerequisites cp
      where cp.course_id = v_course_id
        and cp.status = 'active'
        and not exists (
          select 1
          from public.course_results cr
          join public.course_offerings completed_co on completed_co.id = cr.course_offering_id
          where cr.student_id = v_student_id
            and completed_co.course_id = cp.prerequisite_course_id
            and cr.outcome_code = 'pass'
            and (
              cp.minimum_grade_point is null
              or coalesce(cr.grade_point,0) >= cp.minimum_grade_point
            )
        );

      if v_missing_prerequisites > 0 then
        v_outcome := 'rejected';
        v_decision_code := 'ENROLLMENT_PREREQUISITE_MISSING';
      end if;
    end if;

    if v_outcome is null then
      select coalesce(sum(
        case when c.course_kind = 'course' then c.credit_hours else c.subject_load end
      ),0)
        into v_current_load
      from public.enrollments e
      join public.course_offerings co on co.id = e.course_offering_id
      join public.courses c on c.id = co.course_id
      where e.student_id = v_student_id
        and e.term_id = v_term_id
        and e.enrollment_status = 'active';

      if v_current_load + v_course_load > v_max_load then
        v_outcome := 'rejected';
        v_decision_code := 'ENROLLMENT_MAXIMUM_LOAD_EXCEEDED';
      end if;
    end if;

    if v_outcome is null and v_preferred_section_id is not null then
      select s.id
        into v_selected_section_id
      from public.sections s
      where s.id = v_preferred_section_id
        and s.institution_id = v_institution_id
        and s.campus_id = v_campus_id
        and s.offering_id = v_offering_id
        and s.status = 'open'
        and not app.has_schedule_conflict(v_student_id, s.id)
      for update;

      if v_selected_section_id is not null
         and app.section_remaining_capacity(v_selected_section_id) <= 0 then
        v_selected_section_id := null;
      end if;
    end if;

    if v_outcome is null and v_selected_section_id is null and v_allow_fallback then
      select s.id
        into v_selected_section_id
      from public.sections s
      where s.institution_id = v_institution_id
        and s.campus_id = v_campus_id
        and s.offering_id = v_offering_id
        and s.status = 'open'
        and app.section_remaining_capacity(s.id) > 0
        and not app.has_schedule_conflict(v_student_id, s.id)
      order by app.section_remaining_capacity(s.id) desc, s.code
      for update skip locked
      limit 1;
    end if;

    if v_outcome is null and v_selected_section_id is not null then
      if app.has_schedule_conflict(v_student_id, v_selected_section_id) then
        v_outcome := 'rejected';
        v_decision_code := 'ENROLLMENT_TIMETABLE_CONFLICT';
      elsif app.section_remaining_capacity(v_selected_section_id) <= 0 then
        v_selected_section_id := null;
      else
        insert into public.enrollments (
          institution_id, campus_id, student_id, program_registration_id,
          term_id, course_offering_id, section_id, enrollment_request_item_id,
          enrollment_status
        )
        values (
          v_institution_id, v_campus_id, v_student_id, v_registration_id,
          v_term_id, v_offering_id, v_selected_section_id, v_item_id, 'active'
        )
        returning id into v_enrollment_id;

        v_outcome := 'enrolled';
        v_decision_code := 'ENROLLMENT_ACCEPTED';
      end if;
    end if;

    if v_outcome is null then
      if v_full_behavior = 'waitlist' then
        perform pg_advisory_xact_lock(hashtext(v_offering_id::text));
        select coalesce(max(w.position_number),0) + 1
          into v_position
        from public.waitlist_entries w
        where w.course_offering_id = v_offering_id
          and w.waitlist_status = 'waiting';

        insert into public.waitlist_entries (
          institution_id, campus_id, student_id, enrollment_request_item_id,
          course_offering_id, preferred_section_id, position_number
        )
        values (
          v_institution_id, v_campus_id, v_student_id, v_item_id,
          v_offering_id, v_preferred_section_id, v_position
        )
        returning id into v_waitlist_id;

        v_outcome := 'waitlisted';
        v_decision_code := 'ENROLLMENT_WAITLISTED';
      elsif v_full_behavior = 'manual_review' then
        v_outcome := 'manual_review';
        v_decision_code := 'ENROLLMENT_MANUAL_REVIEW';
      else
        v_outcome := 'rejected';
        v_decision_code := 'ENROLLMENT_ALL_SECTIONS_FULL';
      end if;
    end if;

    update public.enrollment_request_items
    set item_outcome = v_outcome,
        assigned_section_id = v_selected_section_id,
        decision_code = v_decision_code
    where id = v_item_id;

    insert into public.enrollment_decisions (
      institution_id, enrollment_request_id, enrollment_request_item_id,
      decision, decision_code, evidence, correlation_id
    )
    values (
      v_institution_id, v_request_id, v_item_id,
      v_outcome, v_decision_code,
      jsonb_build_object(
        'section_id', v_selected_section_id,
        'enrollment_id', v_enrollment_id,
        'waitlist_id', v_waitlist_id
      ),
      v_correlation_id
    );

    if v_outcome = 'rejected' then
      v_overall := 'rejected';
    elsif v_outcome = 'manual_review' and v_overall <> 'rejected' then
      v_overall := 'manual_review';
    elsif v_outcome = 'waitlisted' and v_overall not in ('rejected','manual_review') then
      v_overall := 'waitlisted';
    end if;

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'request_item_id', v_item_id,
      'course_offering_id', v_offering_id,
      'outcome', v_outcome,
      'decision_code', v_decision_code,
      'section_id', v_selected_section_id,
      'enrollment_id', v_enrollment_id,
      'waitlist_id', v_waitlist_id
    ));
  end loop;

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'enrollment_request_id', v_request_id,
      'overall_outcome', v_overall,
      'items', v_results
    )
  );

  update public.enrollment_requests
  set request_status = case
        when v_overall = 'manual_review' then 'manual_review'::public.business_request_status
        when v_overall = 'rejected' then 'rejected'::public.business_request_status
        else 'completed'::public.business_request_status
      end,
      final_outcome = v_overall,
      result_payload = v_result
  where id = v_request_id;

  select s.primary_email into v_recipient_email
  from public.students s where s.id = v_student_id;

  if v_recipient_email is not null then
    insert into ops.notification_outbox (
      institution_id, campus_id, channel, notification_type, recipient_address,
      subject, template_code, payload, correlation_id, idempotency_key
    )
    values (
      v_institution_id, v_campus_id, 'email', 'enrollment.decision',
      v_recipient_email, 'Enrollment request update', 'enrollment-decision',
      jsonb_build_object(
        'student_id', v_student_id,
        'enrollment_request_id', v_request_id,
        'overall_outcome', v_overall
      ),
      v_correlation_id, v_idempotency_key || ':enrollment-decision'
    )
    on conflict (institution_id, channel, notification_type, idempotency_key) do nothing;
  end if;

  perform app.complete_idempotency(v_idem_id, v_result);

  insert into audit.audit_logs (
    institution_id, campus_id, operation, entity_type, entity_id,
    correlation_id, outcome, details
  )
  values (
    v_institution_id, v_campus_id, v_operation, 'enrollment_request', v_request_id,
    v_correlation_id, 'success', jsonb_build_object('overall_outcome', v_overall)
  );

  return v_result;
exception
  when others then
    v_result := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
    if v_idem_id is not null then
      perform app.fail_idempotency(v_idem_id, v_result);
    end if;
    return v_result;
end;
$function$;

create or replace function public.rpc_decide_enrollment(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'enrollment.decide';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_item_id uuid := nullif(p_request#>>'{payload,enrollment_request_item_id}','')::uuid;
  v_decision public.enrollment_outcome := nullif(p_request#>>'{payload,decision}','')::public.enrollment_outcome;
  v_section_id uuid := nullif(p_request#>>'{payload,section_id}','')::uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_student_id uuid;
  v_request_id uuid;
  v_offering_id uuid;
  v_term_id uuid;
  v_registration_id uuid;
  v_enrollment_id uuid;
  v_result jsonb;
begin
  select er.institution_id, er.campus_id, er.student_id, er.id,
         eri.course_offering_id, er.term_id, er.program_registration_id
    into v_institution_id, v_campus_id, v_student_id, v_request_id,
         v_offering_id, v_term_id, v_registration_id
  from public.enrollment_request_items eri
  join public.enrollment_requests er on er.id = eri.enrollment_request_id
  where eri.id = v_item_id
  for update;

  if v_request_id is null then
    raise exception using errcode = 'P0001', message = 'ENROLLMENT_REQUEST_NOT_FOUND';
  end if;

  if not app.can_access_campus(v_institution_id, v_campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if v_decision not in ('enrolled','rejected','cancelled') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_DECISION_INVALID';
  end if;

  if v_decision = 'enrolled' then
    if v_section_id is null then
      raise exception using errcode = 'P0001', message = 'VALIDATION_SECTION_REQUIRED';
    end if;

    perform 1 from public.sections s
    where s.id = v_section_id
      and s.institution_id = v_institution_id
      and s.campus_id = v_campus_id
      and s.offering_id = v_offering_id
      and s.status = 'open'
    for update;

    if not found then
      raise exception using errcode = 'P0001', message = 'ENROLLMENT_SECTION_INVALID';
    end if;

    if app.section_remaining_capacity(v_section_id) <= 0 then
      raise exception using errcode = 'P0001', message = 'ENROLLMENT_SECTION_FULL';
    end if;

    if app.has_schedule_conflict(v_student_id, v_section_id) then
      raise exception using errcode = 'P0001', message = 'ENROLLMENT_TIMETABLE_CONFLICT';
    end if;

    insert into public.enrollments (
      institution_id, campus_id, student_id, program_registration_id,
      term_id, course_offering_id, section_id, enrollment_request_item_id
    )
    values (
      v_institution_id, v_campus_id, v_student_id, v_registration_id,
      v_term_id, v_offering_id, v_section_id, v_item_id
    )
    on conflict (student_id, course_offering_id)
      where enrollment_status in ('active','completed','failed','incomplete','audit')
    do update set
      section_id = excluded.section_id,
      enrollment_status = 'active',
      updated_at = timezone('utc', now())
    returning id into v_enrollment_id;
  end if;

  update public.enrollment_request_items
  set item_outcome = v_decision,
      assigned_section_id = case when v_decision = 'enrolled' then v_section_id else assigned_section_id end,
      decision_code = case
        when v_decision = 'enrolled' then 'ENROLLMENT_ADMIN_APPROVED'
        when v_decision = 'rejected' then 'ENROLLMENT_ADMIN_REJECTED'
        else 'ENROLLMENT_ADMIN_CANCELLED'
      end
  where id = v_item_id;

  insert into public.enrollment_decisions (
    institution_id, enrollment_request_id, enrollment_request_item_id,
    decision, decision_code, decision_reason, decided_by,
    correlation_id
  )
  values (
    v_institution_id, v_request_id, v_item_id, v_decision,
    case
      when v_decision = 'enrolled' then 'ENROLLMENT_ADMIN_APPROVED'
      when v_decision = 'rejected' then 'ENROLLMENT_ADMIN_REJECTED'
      else 'ENROLLMENT_ADMIN_CANCELLED'
    end,
    nullif(p_request#>>'{payload,reason}',''),
    auth.uid(),
    v_correlation_id
  );

  v_result := app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'enrollment_request_item_id', v_item_id,
      'decision', v_decision,
      'section_id', v_section_id,
      'enrollment_id', v_enrollment_id
    )
  );
  return v_result;
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_promote_waitlist(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'enrollment.waitlist.promote';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_offering_id uuid := nullif(p_request#>>'{payload,course_offering_id}','')::uuid;
  v_section_id uuid := nullif(p_request#>>'{payload,section_id}','')::uuid;
  v_waitlist public.waitlist_entries%rowtype;
  v_request public.enrollment_requests%rowtype;
  v_institution_id uuid;
  v_campus_id uuid;
  v_enrollment_id uuid;
begin
  select co.institution_id, co.campus_id
    into v_institution_id, v_campus_id
  from public.course_offerings co
  where co.id = v_offering_id;

  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'ENROLLMENT_OFFERING_NOT_AVAILABLE';
  end if;

  if not app.is_service_request()
     and not app.can_access_campus(v_institution_id, v_campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_offering_id::text));

  select *
    into v_waitlist
  from public.waitlist_entries w
  where w.course_offering_id = v_offering_id
    and w.waitlist_status = 'waiting'
  order by w.position_number
  for update skip locked
  limit 1;

  if v_waitlist.id is null then
    return app.rpc_success(
      v_operation, v_correlation_id, null,
      jsonb_build_object('promoted', false, 'reason', 'WAITLIST_EMPTY')
    );
  end if;

  if v_section_id is null then
    select s.id into v_section_id
    from public.sections s
    where s.offering_id = v_offering_id
      and s.status = 'open'
      and app.section_remaining_capacity(s.id) > 0
      and not app.has_schedule_conflict(v_waitlist.student_id, s.id)
    order by app.section_remaining_capacity(s.id) desc, s.code
    for update skip locked
    limit 1;
  else
    perform 1 from public.sections s
    where s.id = v_section_id and s.offering_id = v_offering_id and s.status = 'open'
    for update;
  end if;

  if v_section_id is null or app.section_remaining_capacity(v_section_id) <= 0 then
    return app.rpc_success(
      v_operation, v_correlation_id, null,
      jsonb_build_object('promoted', false, 'reason', 'NO_CAPACITY')
    );
  end if;

  select er.* into v_request
  from public.enrollment_request_items eri
  join public.enrollment_requests er on er.id = eri.enrollment_request_id
  where eri.id = v_waitlist.enrollment_request_item_id;

  insert into public.enrollments (
    institution_id, campus_id, student_id, program_registration_id,
    term_id, course_offering_id, section_id, enrollment_request_item_id
  )
  values (
    v_waitlist.institution_id, v_waitlist.campus_id, v_waitlist.student_id,
    v_request.program_registration_id, v_request.term_id, v_offering_id,
    v_section_id, v_waitlist.enrollment_request_item_id
  )
  returning id into v_enrollment_id;

  update public.waitlist_entries
  set waitlist_status = 'promoted',
      promoted_at = timezone('utc', now())
  where id = v_waitlist.id;

  update public.enrollment_request_items
  set item_outcome = 'enrolled',
      assigned_section_id = v_section_id,
      decision_code = 'ENROLLMENT_WAITLIST_PROMOTED'
  where id = v_waitlist.enrollment_request_item_id;

  insert into public.enrollment_decisions (
    institution_id, enrollment_request_id, enrollment_request_item_id,
    decision, decision_code, evidence, decided_by, correlation_id
  )
  values (
    v_waitlist.institution_id, v_request.id, v_waitlist.enrollment_request_item_id,
    'enrolled', 'ENROLLMENT_WAITLIST_PROMOTED',
    jsonb_build_object('waitlist_id', v_waitlist.id, 'section_id', v_section_id),
    auth.uid(), v_correlation_id
  );

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'promoted', true,
      'waitlist_id', v_waitlist.id,
      'student_id', v_waitlist.student_id,
      'section_id', v_section_id,
      'enrollment_id', v_enrollment_id
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_submit_marks_batch(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.batch.submit';
  v_correlation_id uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_idempotency_key text;
  v_payload jsonb;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_existing jsonb;
  v_offering_id uuid;
  v_section_id uuid;
  v_staff_id uuid;
  v_version integer;
  v_batch_id uuid;
  v_row jsonb;
  v_student_id uuid;
  v_enrollment_id uuid;
  v_assessment_id uuid;
  v_marks numeric(8,2);
  v_absent boolean;
  v_missing boolean;
  v_student_number text;
  v_assessment_max numeric(8,2);
  v_valid_count integer := 0;
  v_error_count integer := 0;
  v_warning_count integer := 0;
  v_row_number integer := 0;
  v_result jsonb;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_OBJECT_REQUIRED';
  end if;

  v_correlation_id := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id := nullif(p_request->>'campus_id','')::uuid;
  v_idempotency_key := p_request->>'idempotency_key';
  v_payload := coalesce(p_request->'payload', '{}'::jsonb);
  v_hash := app.request_hash(p_request);
  v_offering_id := nullif(v_payload->>'course_offering_id','')::uuid;
  v_section_id := nullif(v_payload->>'section_id','')::uuid;

  if v_institution_id is null or v_campus_id is null or v_offering_id is null
     or v_section_id is null or btrim(coalesce(v_idempotency_key,'')) = ''
     or jsonb_typeof(v_payload->'marks') <> 'array' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  if app.is_service_request() then
    v_staff_id := nullif(v_payload->>'staff_profile_id','')::uuid;
    if v_staff_id is null and nullif(v_payload->>'teacher_email','') is not null then
      select sp.id into v_staff_id
      from public.staff_profiles sp
      where lower(sp.email) = lower(v_payload->>'teacher_email')
        and sp.status = 'active'
      limit 1;
    end if;
  else
    v_staff_id := app.current_staff_profile_id();
  end if;

  if v_staff_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_TEACHER_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    where ta.staff_profile_id = v_staff_id
      and ta.institution_id = v_institution_id
      and ta.campus_id = v_campus_id
      and ta.offering_id = v_offering_id
      and ta.section_id = v_section_id
      and ta.status = 'active'
      and (ta.valid_from is null or ta.valid_from <= current_date)
      and (ta.valid_to is null or ta.valid_to >= current_date)
  ) and not app.can_access_campus(v_institution_id, v_campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_TEACHER_ASSIGNMENT_REQUIRED';
  end if;

  v_idem := app.begin_idempotency(
    v_institution_id, v_operation, v_idempotency_key, v_hash, v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;
  v_existing := v_idem->'existing_result';

  if v_existing is not null and v_existing <> 'null'::jsonb then
    return v_existing;
  end if;

  perform pg_advisory_xact_lock(hashtext(v_section_id::text));
  select coalesce(max(mb.version_number),0) + 1 into v_version
  from public.marks_batches mb
  where mb.section_id = v_section_id;

  insert into public.marks_batches (
    institution_id, campus_id, offering_id, section_id,
    submitted_by_staff_profile_id, version_number, source_submission_id,
    correlation_id, idempotency_key, request_hash, batch_status
  )
  values (
    v_institution_id, v_campus_id, v_offering_id, v_section_id,
    v_staff_id, v_version, p_request#>>'{source,source_submission_id}',
    v_correlation_id, v_idempotency_key, v_hash, 'draft'
  )
  returning id into v_batch_id;

  for v_row in select value from jsonb_array_elements(v_payload->'marks')
  loop
    v_row_number := v_row_number + 1;
    v_student_number := btrim(coalesce(v_row->>'student_number',''));
    v_assessment_id := nullif(v_row->>'assessment_id','')::uuid;
    v_marks := nullif(v_row->>'marks_obtained','')::numeric;
    v_absent := coalesce((v_row->>'is_absent')::boolean, false);
    v_missing := coalesce((v_row->>'is_missing')::boolean, false);
    v_student_id := null;
    v_enrollment_id := null;
    v_assessment_max := null;

    select s.id, e.id
      into v_student_id, v_enrollment_id
    from public.students s
    join public.enrollments e
      on e.student_id = s.id
     and e.section_id = v_section_id
     and e.course_offering_id = v_offering_id
     and e.enrollment_status = 'active'
    where s.institution_id = v_institution_id
      and upper(s.student_number) = upper(v_student_number)
    limit 1;

    select a.maximum_marks into v_assessment_max
    from public.assessments a
    where a.id = v_assessment_id
      and a.institution_id = v_institution_id
      and a.offering_id = v_offering_id
      and (a.section_id is null or a.section_id = v_section_id)
      and a.status = 'active';

    if v_student_id is null then
      insert into public.marks_validation_issues (
        institution_id, marks_batch_id, issue_code, severity,
        student_number, row_number, message
      )
      values (
        v_institution_id, v_batch_id, 'MARKS_UNKNOWN_OR_UNENROLLED_STUDENT',
        'error', v_student_number, v_row_number,
        'Student is not an active member of the section.'
      );
      v_error_count := v_error_count + 1;
      continue;
    end if;

    if v_assessment_max is null then
      insert into public.marks_validation_issues (
        institution_id, marks_batch_id, issue_code, severity,
        student_number, row_number, message
      )
      values (
        v_institution_id, v_batch_id, 'MARKS_ASSESSMENT_INVALID',
        'error', v_student_number, v_row_number,
        'Assessment does not belong to the offering or section.'
      );
      v_error_count := v_error_count + 1;
      continue;
    end if;

    if exists (
      select 1 from public.student_marks sm
      where sm.marks_batch_id = v_batch_id
        and sm.assessment_id = v_assessment_id
        and sm.student_id = v_student_id
    ) then
      insert into public.marks_validation_issues (
        institution_id, marks_batch_id, issue_code, severity,
        student_number, row_number, message
      )
      values (
        v_institution_id, v_batch_id, 'MARKS_DUPLICATE_STUDENT_ASSESSMENT',
        'error', v_student_number, v_row_number,
        'The student and assessment appear more than once.'
      );
      v_error_count := v_error_count + 1;
      continue;
    end if;

    if (v_marks is null and not v_absent and not v_missing)
       or (v_marks is not null and (v_absent or v_missing))
       or (v_absent and v_missing) then
      insert into public.marks_validation_issues (
        institution_id, marks_batch_id, issue_code, severity,
        student_number, row_number, message
      )
      values (
        v_institution_id, v_batch_id, 'MARKS_VALUE_STATE_INVALID',
        'error', v_student_number, v_row_number,
        'Provide marks or one absence/missing state.'
      );
      v_error_count := v_error_count + 1;
      continue;
    end if;

    if v_marks is not null and (v_marks < 0 or v_marks > v_assessment_max) then
      insert into public.marks_validation_issues (
        institution_id, marks_batch_id, issue_code, severity,
        student_number, row_number, message,
        details
      )
      values (
        v_institution_id, v_batch_id, 'MARKS_OUT_OF_RANGE',
        'error', v_student_number, v_row_number,
        'Marks are outside the permitted range.',
        jsonb_build_object('maximum_marks', v_assessment_max)
      );
      v_error_count := v_error_count + 1;
      continue;
    end if;

    insert into public.student_marks (
      institution_id, marks_batch_id, assessment_id, student_id,
      enrollment_id, marks_obtained, is_absent, is_missing, remarks
    )
    values (
      v_institution_id, v_batch_id, v_assessment_id, v_student_id,
      v_enrollment_id, v_marks, v_absent, v_missing, nullif(v_row->>'remarks','')
    );
    v_valid_count := v_valid_count + 1;
  end loop;

  update public.marks_batches
  set validation_summary = jsonb_build_object(
    'valid_rows', v_valid_count,
    'error_count', v_error_count,
    'warning_count', v_warning_count,
    'total_rows', v_row_number
  )
  where id = v_batch_id;

  v_result := app.rpc_success(
    v_operation, v_correlation_id, v_idempotency_key,
    jsonb_build_object(
      'marks_batch_id', v_batch_id,
      'version_number', v_version,
      'status', 'draft',
      'validation_summary', jsonb_build_object(
        'valid_rows', v_valid_count,
        'error_count', v_error_count,
        'warning_count', v_warning_count,
        'total_rows', v_row_number
      )
    ),
    case when v_error_count > 0
      then jsonb_build_array('The batch remains draft until validation errors are resolved.')
      else '[]'::jsonb
    end
  );

  perform app.complete_idempotency(v_idem_id, v_result);

  insert into audit.audit_logs (
    institution_id, campus_id, actor_staff_profile_id, operation,
    entity_type, entity_id, correlation_id, outcome, details
  )
  values (
    v_institution_id, v_campus_id, v_staff_id, v_operation,
    'marks_batch', v_batch_id, v_correlation_id, 'success',
    jsonb_build_object('error_count', v_error_count, 'valid_rows', v_valid_count)
  );

  return v_result;
exception when others then
  v_result := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
  if v_idem_id is not null then
    perform app.fail_idempotency(v_idem_id, v_result);
  end if;
  return v_result;
end;
$function$;

create or replace function public.rpc_finalize_marks_batch(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.batch.finalize';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_batch_id uuid := nullif(p_request#>>'{payload,marks_batch_id}','')::uuid;
  v_batch public.marks_batches%rowtype;
  v_error_count integer;
begin
  select * into v_batch
  from public.marks_batches mb
  where mb.id = v_batch_id
  for update;

  if v_batch.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FOUND';
  end if;

  if not app.is_service_request()
     and v_batch.submitted_by_staff_profile_id <> app.current_staff_profile_id()
     and not app.can_access_campus(v_batch.institution_id, v_batch.campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if v_batch.batch_status in ('finalized','approved','rejected') then
    return app.rpc_success(
      v_operation, v_correlation_id, null,
      jsonb_build_object('marks_batch_id', v_batch.id, 'status', v_batch.batch_status)
    );
  end if;

  select count(*)::integer into v_error_count
  from public.marks_validation_issues mvi
  where mvi.marks_batch_id = v_batch_id and mvi.severity = 'error';

  if v_error_count > 0 then
    raise exception using errcode = 'P0001', message = 'MARKS_VALIDATION_ERRORS_EXIST';
  end if;

  if not exists (select 1 from public.student_marks sm where sm.marks_batch_id = v_batch_id) then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_EMPTY';
  end if;

  update public.marks_batches
  set batch_status = 'finalized',
      finalized_at = timezone('utc', now())
  where id = v_batch_id;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object('marks_batch_id', v_batch_id, 'status', 'finalized')
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_decide_marks_batch(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.batch.decide';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_batch_id uuid := nullif(p_request#>>'{payload,marks_batch_id}','')::uuid;
  v_decision public.approval_decision := nullif(p_request#>>'{payload,decision}','')::public.approval_decision;
  v_batch public.marks_batches%rowtype;
  v_student_id uuid;
begin
  select * into v_batch
  from public.marks_batches mb
  where mb.id = v_batch_id
  for update;

  if v_batch.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FOUND';
  end if;

  if not app.can_access_campus(v_batch.institution_id, v_batch.campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if v_batch.batch_status <> 'finalized' then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FINALIZED';
  end if;

  if v_decision not in ('approved','rejected','returned') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_DECISION_INVALID';
  end if;

  insert into public.marks_approval_history (
    institution_id, marks_batch_id, decision, reason,
    decided_by, correlation_id
  )
  values (
    v_batch.institution_id, v_batch_id, v_decision,
    nullif(p_request#>>'{payload,reason}',''),
    auth.uid(), v_correlation_id
  );

  update public.marks_batches
  set batch_status = case
        when v_decision = 'approved' then 'approved'::public.marks_batch_status
        else 'rejected'::public.marks_batch_status
      end,
      approved_at = case when v_decision = 'approved' then timezone('utc', now()) else null end,
      approved_by = case when v_decision = 'approved' then auth.uid() else null end
  where id = v_batch_id;

  if v_decision = 'approved' then
    for v_student_id in
      select distinct sm.student_id
      from public.student_marks sm
      where sm.marks_batch_id = v_batch_id
    loop
      perform app.calculate_course_result(v_student_id, v_batch.offering_id, v_correlation_id);
    end loop;
  end if;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'marks_batch_id', v_batch_id,
      'decision', v_decision,
      'status', case when v_decision = 'approved' then 'approved' else 'rejected' end
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
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
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_idempotency_key text := p_request->>'idempotency_key';
  v_batch_id uuid := nullif(p_request#>>'{payload,marks_batch_id}','')::uuid;
  v_student_mark_id uuid := nullif(p_request#>>'{payload,student_mark_id}','')::uuid;
  v_staff_id uuid := app.current_staff_profile_id();
  v_student_id uuid := app.current_student_id();
  v_correction_id uuid;
begin
  if btrim(coalesce(v_idempotency_key,'')) = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  if not app.is_service_request()
     and v_staff_id is null and v_student_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_LOGIN_REQUIRED';
  end if;

  if not exists (
    select 1 from public.marks_batches mb
    where mb.id = v_batch_id
      and mb.institution_id = v_institution_id
      and mb.campus_id = v_campus_id
      and (
        app.is_service_request()
        or app.can_access_campus(v_institution_id, v_campus_id)
        or mb.submitted_by_staff_profile_id = v_staff_id
        or exists (
          select 1 from public.student_marks sm
          where sm.id = v_student_mark_id
            and sm.marks_batch_id = mb.id
            and sm.student_id = v_student_id
        )
      )
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  insert into public.mark_correction_requests (
    institution_id, campus_id, marks_batch_id, student_mark_id,
    requested_by_staff_profile_id, requested_by_student_id, reason,
    proposed_marks, correlation_id, idempotency_key
  )
  values (
    v_institution_id, v_campus_id, v_batch_id, v_student_mark_id,
    v_staff_id, v_student_id,
    btrim(coalesce(p_request#>>'{payload,reason}','')),
    nullif(p_request#>>'{payload,proposed_marks}','')::numeric,
    v_correlation_id, v_idempotency_key
  )
  on conflict (institution_id, idempotency_key)
  do update set updated_at = public.mark_correction_requests.updated_at
  returning id into v_correction_id;

  return app.rpc_success(
    v_operation, v_correlation_id, v_idempotency_key,
    jsonb_build_object('correction_request_id', v_correction_id, 'status', 'requested')
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
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
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_correction_id uuid := nullif(p_request#>>'{payload,correction_request_id}','')::uuid;
  v_decision public.approval_decision := nullif(p_request#>>'{payload,decision}','')::public.approval_decision;
  v_correction public.mark_correction_requests%rowtype;
  v_mark public.student_marks%rowtype;
  v_batch public.marks_batches%rowtype;
begin
  select * into v_correction
  from public.mark_correction_requests mcr
  where mcr.id = v_correction_id
  for update;

  if v_correction.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_NOT_FOUND';
  end if;

  if not app.can_access_campus(v_correction.institution_id, v_correction.campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if v_correction.correction_status <> 'requested' then
    return app.rpc_success(
      v_operation, v_correlation_id, null,
      jsonb_build_object(
        'correction_request_id', v_correction.id,
        'status', v_correction.correction_status
      )
    );
  end if;

  if v_decision = 'approved' then
    if v_correction.student_mark_id is null or v_correction.proposed_marks is null then
      raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_VALUE_REQUIRED';
    end if;

    select * into v_mark from public.student_marks where id = v_correction.student_mark_id for update;
    select * into v_batch from public.marks_batches where id = v_mark.marks_batch_id;

    update public.student_marks
    set marks_obtained = v_correction.proposed_marks,
        is_absent = false,
        is_missing = false,
        updated_at = timezone('utc', now())
    where id = v_mark.id;

    update public.mark_correction_requests
    set correction_status = 'applied',
        decision_reason = nullif(p_request#>>'{payload,reason}',''),
        decided_by = auth.uid(),
        decided_at = timezone('utc', now()),
        applied_at = timezone('utc', now())
    where id = v_correction.id;

    perform app.calculate_course_result(
      v_mark.student_id, v_batch.offering_id, v_correlation_id
    );
  else
    update public.mark_correction_requests
    set correction_status = 'rejected',
        decision_reason = nullif(p_request#>>'{payload,reason}',''),
        decided_by = auth.uid(),
        decided_at = timezone('utc', now())
    where id = v_correction.id;
  end if;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'correction_request_id', v_correction.id,
      'status', case when v_decision = 'approved' then 'applied' else 'rejected' end
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
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
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_offering_id uuid := nullif(p_request#>>'{payload,course_offering_id}','')::uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_term_id uuid;
  v_student_id uuid;
  v_result_count integer := 0;
  v_records jsonb := '[]'::jsonb;
  v_academic jsonb;
begin
  select co.institution_id, co.campus_id, co.term_id
    into v_institution_id, v_campus_id, v_term_id
  from public.course_offerings co
  where co.id = v_offering_id;

  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'RESULT_OFFERING_NOT_FOUND';
  end if;

  if not app.can_access_campus(v_institution_id, v_campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if not exists (
    select 1 from public.marks_batches mb
    where mb.offering_id = v_offering_id and mb.batch_status = 'approved'
  ) then
    raise exception using errcode = 'P0001', message = 'RESULT_APPROVED_MARKS_REQUIRED';
  end if;

  for v_student_id in
    select distinct e.student_id
    from public.enrollments e
    where e.course_offering_id = v_offering_id
      and e.enrollment_status not in ('withdrawn','cancelled')
  loop
    perform app.calculate_course_result(v_student_id, v_offering_id, v_correlation_id);

    update public.course_results
    set result_status = 'published',
        approved_at = coalesce(approved_at, timezone('utc', now())),
        published_at = timezone('utc', now())
    where student_id = v_student_id
      and course_offering_id = v_offering_id;

    v_academic := app.recalculate_academic_record(
      v_student_id, v_term_id, v_correlation_id
    );

    update public.semester_results
    set result_status = 'published',
        published_at = timezone('utc', now())
    where student_id = v_student_id and term_id = v_term_id;

    v_records := v_records || jsonb_build_array(
      jsonb_build_object('student_id', v_student_id, 'academic_record', v_academic)
    );
    v_result_count := v_result_count + 1;
  end loop;

  insert into ops.notification_outbox (
    institution_id, campus_id, channel, notification_type, recipient_address,
    subject, template_code, payload, correlation_id, idempotency_key
  )
  select
    s.institution_id, s.campus_id, 'email', 'results.published',
    s.primary_email, 'Results published', 'results-published',
    jsonb_build_object('student_id', s.id, 'course_offering_id', v_offering_id),
    v_correlation_id,
    v_offering_id::text || ':' || s.id::text || ':results-published'
  from public.students s
  join public.enrollments e on e.student_id = s.id
  where e.course_offering_id = v_offering_id
    and s.primary_email is not null
  on conflict (institution_id, channel, notification_type, idempotency_key) do nothing;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'course_offering_id', v_offering_id,
      'published_student_count', v_result_count,
      'records', v_records
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_create_transcript_request(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'transcript.request.create';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_idempotency_key text := p_request->>'idempotency_key';
  v_student_id uuid := nullif(p_request#>>'{payload,student_id}','')::uuid;
  v_recipient_email text := lower(btrim(coalesce(p_request#>>'{payload,recipient_email}','')));
  v_reference_prefix text;
  v_reference text;
  v_request_id uuid;
  v_authorized boolean := false;
begin
  if v_student_id is null or v_institution_id is null or v_campus_id is null
     or btrim(coalesce(v_idempotency_key,'')) = '' or position('@' in v_recipient_email) <= 1 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  v_authorized := app.is_service_request()
    or app.student_owns(v_student_id)
    or app.can_access_campus(v_institution_id, v_campus_id);

  if not v_authorized then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if not exists (
    select 1 from public.course_results cr
    where cr.student_id = v_student_id and cr.result_status = 'published'
  ) then
    raise exception using errcode = 'P0001', message = 'TRANSCRIPT_ACADEMIC_RECORD_MISSING';
  end if;

  select ts.reference_prefix into v_reference_prefix
  from public.transcript_settings ts
  where ts.institution_id = v_institution_id
    and ts.status = 'active'
    and ts.effective_from <= current_date
    and (ts.effective_to is null or ts.effective_to >= current_date)
  order by ts.version desc
  limit 1;

  v_reference_prefix := coalesce(v_reference_prefix, 'TR');

  select tr.id, tr.reference_number
    into v_request_id, v_reference
  from public.transcript_requests tr
  where tr.institution_id = v_institution_id
    and tr.idempotency_key = v_idempotency_key
  for update;

  if v_request_id is null then
    perform pg_advisory_xact_lock(hashtext(v_institution_id::text || ':transcript'));
    v_reference := v_reference_prefix || '-' ||
      to_char(current_date, 'YYYY') || '-' ||
      lpad((
        select (count(*) + 1)::text
        from public.transcript_requests tr
        where tr.institution_id = v_institution_id
          and date_part('year', tr.created_at) = date_part('year', timezone('utc', now()))
      ), 6, '0');

    insert into public.transcript_requests (
      institution_id, campus_id, student_id, requested_by_auth_user_id,
      recipient_email, purpose, correlation_id, idempotency_key,
      request_status, reference_number, verification_code, authorized_at
    )
    values (
      v_institution_id, v_campus_id, v_student_id, auth.uid(),
      v_recipient_email, nullif(p_request#>>'{payload,purpose}',''),
      v_correlation_id, v_idempotency_key, 'authorized',
      v_reference, upper(substr(encode(gen_random_bytes(8),'hex'),1,12)),
      timezone('utc', now())
    )
    returning id into v_request_id;
  end if;

  return app.rpc_success(
    v_operation, v_correlation_id, v_idempotency_key,
    jsonb_build_object(
      'transcript_request_id', v_request_id,
      'reference_number', v_reference,
      'status', 'authorized'
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_get_transcript_model(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'transcript.model.get';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_request_id uuid := nullif(p_request#>>'{payload,transcript_request_id}','')::uuid;
  v_request public.transcript_requests%rowtype;
  v_model jsonb;
begin
  select * into v_request
  from public.transcript_requests tr
  where tr.id = v_request_id;

  if v_request.id is null then
    raise exception using errcode = 'P0001', message = 'TRANSCRIPT_REQUEST_NOT_FOUND';
  end if;

  if not app.is_service_request()
     and not app.student_owns(v_request.student_id)
     and not app.can_access_campus(v_request.institution_id, v_request.campus_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  select jsonb_build_object(
    'transcript_request_id', v_request.id,
    'reference_number', v_request.reference_number,
    'verification_code', v_request.verification_code,
    'issue_date', current_date,
    'institution', jsonb_build_object(
      'id', i.id,
      'code', i.code,
      'name', i.name,
      'institution_type', i.institution_type,
      'logo_url', i.logo_url,
      'timezone', i.timezone
    ),
    'campus', jsonb_build_object(
      'id', c.id,
      'code', c.code,
      'name', c.name,
      'city', c.city,
      'country_code', c.country_code
    ),
    'student', jsonb_build_object(
      'id', s.id,
      'student_number', s.student_number,
      'full_name', s.full_name,
      'date_of_birth', s.date_of_birth,
      'status', s.status
    ),
    'program', jsonb_build_object(
      'id', p.id,
      'code', p.code,
      'name', p.name,
      'level_name', p.level_name,
      'academic_model', p.academic_model
    ),
    'terms', coalesce((
      select jsonb_agg(term_model order by term_starts_on)
      from (
        select
          t.starts_on as term_starts_on,
          jsonb_build_object(
            'term_id', t.id,
            'term_code', t.code,
            'term_name', t.name,
            'academic_year', ay.name,
            'courses', coalesce((
              select jsonb_agg(jsonb_build_object(
                'course_code', course.code,
                'course_title', course.title,
                'credit_hours', cr.credit_hours,
                'total_score', cr.total_score,
                'letter_grade', cr.letter_grade,
                'grade_point', cr.grade_point,
                'outcome_code', cr.outcome_code
              ) order by course.code)
              from public.course_results cr
              join public.course_offerings co on co.id = cr.course_offering_id
              join public.courses course on course.id = co.course_id
              where cr.student_id = s.id
                and cr.term_id = t.id
                and cr.result_status = 'published'
            ), '[]'::jsonb),
            'semester_result', (
              select jsonb_build_object(
                'attempted_credits', sr.attempted_credits,
                'earned_credits', sr.earned_credits,
                'gpa', sr.gpa,
                'standing_code', sr.standing_code,
                'at_risk', sr.at_risk
              )
              from public.semester_results sr
              where sr.student_id = s.id and sr.term_id = t.id
            )
          ) as term_model
        from public.terms t
        join public.academic_years ay on ay.id = t.academic_year_id
        where exists (
          select 1 from public.course_results cr
          where cr.student_id = s.id
            and cr.term_id = t.id
            and cr.result_status = 'published'
        )
      ) term_rows
    ), '[]'::jsonb),
    'cumulative', (
      select jsonb_build_object(
        'attempted_credits', cr.attempted_credits,
        'earned_credits', cr.earned_credits,
        'cgpa', cr.cgpa,
        'standing_code', cr.standing_code,
        'at_risk', cr.at_risk
      )
      from public.cumulative_results cr
      where cr.student_id = s.id and cr.program_registration_id = spr.id
    ),
    'disclaimer', (
      select ts.disclaimer
      from public.transcript_settings ts
      where ts.institution_id = s.institution_id and ts.status = 'active'
      order by ts.version desc limit 1
    )
  )
    into v_model
  from public.students s
  join public.institutions i on i.id = s.institution_id
  join public.campuses c on c.id = s.campus_id
  join public.student_program_registrations spr
    on spr.student_id = s.id and spr.registration_status = 'active'
  join public.programs p on p.id = spr.program_id
  where s.id = v_request.student_id
  order by spr.created_at desc
  limit 1;

  if v_model is null then
    raise exception using errcode = 'P0001', message = 'TRANSCRIPT_ACADEMIC_RECORD_MISSING';
  end if;

  return app.rpc_success(
    v_operation, v_correlation_id, null, v_model
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_record_transcript_document(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'transcript.document.record';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_request_id uuid := nullif(p_request#>>'{payload,transcript_request_id}','')::uuid;
  v_request public.transcript_requests%rowtype;
  v_document_id uuid;
  v_outbox_id uuid;
  v_delivery_id uuid;
  v_version integer;
begin
  perform app.require_service();

  select * into v_request
  from public.transcript_requests tr
  where tr.id = v_request_id
  for update;

  if v_request.id is null then
    raise exception using errcode = 'P0001', message = 'TRANSCRIPT_REQUEST_NOT_FOUND';
  end if;

  select coalesce(max(td.document_version),0) + 1 into v_version
  from public.transcript_documents td
  where td.transcript_request_id = v_request_id;

  insert into public.transcript_documents (
    institution_id, transcript_request_id, document_version,
    google_doc_id, pdf_drive_file_id, pdf_file_url, checksum_sha256
  )
  values (
    v_request.institution_id, v_request.id, v_version,
    nullif(p_request#>>'{payload,google_doc_id}',''),
    nullif(p_request#>>'{payload,pdf_drive_file_id}',''),
    nullif(p_request#>>'{payload,pdf_file_url}',''),
    nullif(p_request#>>'{payload,checksum_sha256}','')
  )
  returning id into v_document_id;

  update public.transcript_requests
  set request_status = 'ready',
      completed_at = timezone('utc', now()),
      error_code = null,
      sanitized_error_message = null
  where id = v_request.id;

  insert into ops.notification_outbox (
    institution_id, campus_id, channel, notification_type,
    recipient_address, subject, template_code, payload,
    correlation_id, idempotency_key
  )
  values (
    v_request.institution_id, v_request.campus_id, 'email',
    'transcript.ready', v_request.recipient_email,
    'Your transcript is ready', 'transcript-ready',
    jsonb_build_object(
      'transcript_request_id', v_request.id,
      'transcript_document_id', v_document_id,
      'reference_number', v_request.reference_number,
      'pdf_file_url', nullif(p_request#>>'{payload,pdf_file_url}','')
    ),
    v_correlation_id, v_request.idempotency_key || ':transcript-ready'
  )
  on conflict (institution_id, channel, notification_type, idempotency_key)
  do update set payload = excluded.payload, updated_at = timezone('utc', now())
  returning id into v_outbox_id;

  insert into public.transcript_delivery_records (
    institution_id, transcript_request_id, transcript_document_id,
    recipient_email, outbox_id, delivery_status
  )
  values (
    v_request.institution_id, v_request.id, v_document_id,
    v_request.recipient_email, v_outbox_id, 'pending'
  )
  returning id into v_delivery_id;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'transcript_request_id', v_request.id,
      'transcript_document_id', v_document_id,
      'delivery_record_id', v_delivery_id,
      'outbox_id', v_outbox_id,
      'status', 'ready'
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_create_hec_report_run(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'report.hec.create';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_idempotency_key text := p_request->>'idempotency_key';
  v_year_id uuid := nullif(p_request#>>'{payload,academic_year_id}','')::uuid;
  v_term_id uuid := nullif(p_request#>>'{payload,term_id}','')::uuid;
  v_program_id uuid := nullif(p_request#>>'{payload,program_id}','')::uuid;
  v_run_id uuid;
  v_template_label text;
begin
  if not app.can_administer_institution(v_institution_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if v_institution_id is null or v_year_id is null
     or btrim(coalesce(v_idempotency_key,'')) = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  select hrs.template_label into v_template_label
  from public.hec_report_settings hrs
  where hrs.institution_id = v_institution_id and hrs.status = 'active'
  order by hrs.version desc limit 1;

  v_template_label := coalesce(v_template_label, 'Demonstration HEC Enrollment Format');

  insert into ops.hec_report_runs (
    institution_id, campus_id, academic_year_id, term_id, program_id,
    requested_by, correlation_id, idempotency_key, filters,
    template_label
  )
  values (
    v_institution_id, v_campus_id, v_year_id, v_term_id, v_program_id,
    auth.uid(), v_correlation_id, v_idempotency_key,
    jsonb_build_object(
      'campus_id', v_campus_id,
      'academic_year_id', v_year_id,
      'term_id', v_term_id,
      'program_id', v_program_id
    ),
    v_template_label
  )
  on conflict (institution_id, idempotency_key)
  do update set updated_at = ops.hec_report_runs.updated_at
  returning id into v_run_id;

  return app.rpc_success(
    v_operation, v_correlation_id, v_idempotency_key,
    jsonb_build_object(
      'hec_report_run_id', v_run_id,
      'status', 'pending',
      'template_label', v_template_label,
      'is_demonstration_template', true
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_get_hec_enrollment_data(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'report.hec.data.get';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_run_id uuid := nullif(p_request#>>'{payload,hec_report_run_id}','')::uuid;
  v_run ops.hec_report_runs%rowtype;
  v_rows jsonb;
begin
  select * into v_run from ops.hec_report_runs hr where hr.id = v_run_id;

  if v_run.id is null then
    raise exception using errcode = 'P0001', message = 'REPORT_RUN_NOT_FOUND';
  end if;

  if not app.is_service_request()
     and not app.can_administer_institution(v_run.institution_id) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  select coalesce(jsonb_agg(row_data order by student_number, course_code), '[]'::jsonb)
    into v_rows
  from (
    select
      s.student_number,
      s.full_name,
      i.name as institution_name,
      c.name as campus_name,
      p.code as program_code,
      p.name as program_name,
      ay.code as academic_year_code,
      t.code as term_code,
      course.code as course_code,
      course.title as course_title,
      sec.code as section_code,
      e.enrollment_status,
      e.enrolled_at,
      jsonb_build_object(
        'student_number', s.student_number,
        'student_name', s.full_name,
        'institution', i.name,
        'campus', c.name,
        'program_code', p.code,
        'program_name', p.name,
        'academic_year', ay.code,
        'term', t.code,
        'course_code', course.code,
        'course_title', course.title,
        'section_code', sec.code,
        'enrollment_status', e.enrollment_status,
        'enrolled_at', e.enrolled_at
      ) as row_data
    from public.enrollments e
    join public.students s on s.id = e.student_id
    join public.institutions i on i.id = e.institution_id
    join public.campuses c on c.id = e.campus_id
    join public.student_program_registrations spr on spr.id = e.program_registration_id
    join public.programs p on p.id = spr.program_id
    join public.course_offerings co on co.id = e.course_offering_id
    join public.courses course on course.id = co.course_id
    join public.sections sec on sec.id = e.section_id
    join public.terms t on t.id = e.term_id
    join public.academic_years ay on ay.id = t.academic_year_id
    where e.institution_id = v_run.institution_id
      and ay.id = v_run.academic_year_id
      and (v_run.campus_id is null or e.campus_id = v_run.campus_id)
      and (v_run.term_id is null or e.term_id = v_run.term_id)
      and (v_run.program_id is null or spr.program_id = v_run.program_id)
      and e.enrollment_status in ('active','completed')
  ) report_rows;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'hec_report_run_id', v_run.id,
      'template_label', v_run.template_label,
      'is_demonstration_template', true,
      'row_count', jsonb_array_length(v_rows),
      'rows', v_rows
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_record_generated_report(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'report.generated.record';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_run_id uuid := nullif(p_request#>>'{payload,hec_report_run_id}','')::uuid;
  v_run ops.hec_report_runs%rowtype;
  v_file jsonb;
  v_file_ids jsonb := '[]'::jsonb;
  v_file_id uuid;
  v_recipient text;
begin
  perform app.require_service();

  select * into v_run from ops.hec_report_runs hr where hr.id = v_run_id for update;
  if v_run.id is null then
    raise exception using errcode = 'P0001', message = 'REPORT_RUN_NOT_FOUND';
  end if;

  if jsonb_typeof(p_request#>'{payload,files}') <> 'array' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REPORT_FILES_REQUIRED';
  end if;

  for v_file in select value from jsonb_array_elements(p_request#>'{payload,files}')
  loop
    insert into ops.generated_report_files (
      institution_id, hec_report_run_id, report_type, file_format,
      storage_provider, storage_object_id, file_url, checksum_sha256
    )
    values (
      v_run.institution_id, v_run.id, 'hec_enrollment',
      v_file->>'file_format', v_file->>'storage_provider',
      v_file->>'storage_object_id', nullif(v_file->>'file_url',''),
      nullif(v_file->>'checksum_sha256','')
    )
    returning id into v_file_id;

    v_file_ids := v_file_ids || jsonb_build_array(v_file_id);
  end loop;

  update ops.hec_report_runs
  set job_status = 'completed',
      completed_at = timezone('utc', now()),
      error_code = null,
      sanitized_error_message = null
  where id = v_run.id;

  select sp.email into v_recipient
  from public.staff_profiles sp
  where sp.auth_user_id = v_run.requested_by;

  if v_recipient is not null then
    insert into ops.notification_outbox (
      institution_id, campus_id, channel, notification_type,
      recipient_address, subject, template_code, payload,
      correlation_id, idempotency_key
    )
    values (
      v_run.institution_id, v_run.campus_id, 'email', 'report.hec.ready',
      v_recipient, 'HEC enrollment report is ready', 'hec-report-ready',
      jsonb_build_object('hec_report_run_id', v_run.id, 'file_ids', v_file_ids),
      v_correlation_id, v_run.idempotency_key || ':hec-ready'
    )
    on conflict (institution_id, channel, notification_type, idempotency_key) do nothing;
  end if;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'hec_report_run_id', v_run.id,
      'status', 'completed',
      'generated_file_ids', v_file_ids
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_search_students(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'student.search';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_query text := btrim(coalesce(p_request#>>'{payload,query}',''));
  v_limit integer := least(greatest(coalesce(nullif(p_request#>>'{payload,limit}','')::integer,20),1),100);
  v_rows jsonb;
begin
  if v_institution_id is null or v_query = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_SEARCH_REQUIRED';
  end if;

  if not app.is_service_request()
     and not (
       app.can_administer_institution(v_institution_id)
       or (v_campus_id is not null and app.can_access_campus(v_institution_id, v_campus_id))
     ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  select coalesce(jsonb_agg(row_data), '[]'::jsonb)
    into v_rows
  from (
    select jsonb_build_object(
      'student_id', s.id,
      'student_number', s.student_number,
      'full_name', s.full_name,
      'primary_email', s.primary_email,
      'campus_id', s.campus_id,
      'status', s.status,
      'program', (
        select jsonb_build_object('program_id', p.id, 'code', p.code, 'name', p.name)
        from public.student_program_registrations spr
        join public.programs p on p.id = spr.program_id
        where spr.student_id = s.id and spr.registration_status = 'active'
        order by spr.created_at desc limit 1
      ),
      'academic', (
        select jsonb_build_object(
          'cgpa', cr.cgpa,
          'standing_code', cr.standing_code,
          'at_risk', cr.at_risk
        )
        from public.cumulative_results cr
        where cr.student_id = s.id
        order by cr.calculated_at desc limit 1
      )
    ) as row_data
    from public.students s
    where s.institution_id = v_institution_id
      and (v_campus_id is null or s.campus_id = v_campus_id)
      and (
        upper(s.student_number) like '%' || upper(v_query) || '%'
        or lower(s.full_name) like '%' || lower(v_query) || '%'
        or lower(coalesce(s.primary_email,'')) like '%' || lower(v_query) || '%'
        or coalesce(s.cnic_hash,'') = v_query
      )
    order by s.student_number
    limit v_limit
  ) q;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object('count', jsonb_array_length(v_rows), 'students', v_rows)
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_get_dashboard_snapshot(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'dashboard.snapshot.get';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_term_id uuid := nullif(p_request#>>'{payload,term_id}','')::uuid;
  v_snapshot jsonb;
begin
  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_INSTITUTION_REQUIRED';
  end if;

  if not app.is_service_request()
     and not (
       app.can_administer_institution(v_institution_id)
       or (v_campus_id is not null and app.can_access_campus(v_institution_id, v_campus_id))
     ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  select jsonb_build_object(
    'generated_at', timezone('utc', now()),
    'institution_id', v_institution_id,
    'campus_id', v_campus_id,
    'term_id', v_term_id,
    'students', jsonb_build_object(
      'total', (select count(*) from public.students s
        where s.institution_id = v_institution_id
          and (v_campus_id is null or s.campus_id = v_campus_id)),
      'active', (select count(*) from public.students s
        where s.institution_id = v_institution_id
          and s.status = 'active'
          and (v_campus_id is null or s.campus_id = v_campus_id)),
      'at_risk', (select count(*) from public.cumulative_results cr
        where cr.institution_id = v_institution_id
          and cr.at_risk
          and (v_campus_id is null or cr.campus_id = v_campus_id))
    ),
    'enrollment', jsonb_build_object(
      'active_count', (select count(*) from public.enrollments e
        where e.institution_id = v_institution_id
          and e.enrollment_status = 'active'
          and (v_campus_id is null or e.campus_id = v_campus_id)
          and (v_term_id is null or e.term_id = v_term_id)),
      'waitlist_count', (select count(*) from public.waitlist_entries w
        where w.institution_id = v_institution_id
          and w.waitlist_status = 'waiting'
          and (v_campus_id is null or w.campus_id = v_campus_id)),
      'rejected_requests', (select count(*) from public.enrollment_requests er
        where er.institution_id = v_institution_id
          and er.final_outcome = 'rejected'
          and (v_campus_id is null or er.campus_id = v_campus_id)
          and (v_term_id is null or er.term_id = v_term_id)),
      'sections', coalesce((
        select jsonb_agg(jsonb_build_object(
          'section_id', scs.section_id,
          'section_code', scs.section_code,
          'capacity', scs.capacity,
          'enrolled_count', scs.enrolled_count,
          'remaining_capacity', scs.remaining_capacity,
          'waitlist_count', scs.waitlist_count
        ) order by scs.section_code)
        from reporting.section_capacity_snapshot scs
        where scs.institution_id = v_institution_id
          and (v_campus_id is null or scs.campus_id = v_campus_id)
          and (v_term_id is null or scs.term_id = v_term_id)
      ), '[]'::jsonb)
    ),
    'marks', jsonb_build_object(
      'draft_batches', (select count(*) from public.marks_batches mb
        where mb.institution_id = v_institution_id
          and mb.batch_status = 'draft'
          and (v_campus_id is null or mb.campus_id = v_campus_id)),
      'finalized_batches', (select count(*) from public.marks_batches mb
        where mb.institution_id = v_institution_id
          and mb.batch_status = 'finalized'
          and (v_campus_id is null or mb.campus_id = v_campus_id)),
      'approved_batches', (select count(*) from public.marks_batches mb
        where mb.institution_id = v_institution_id
          and mb.batch_status = 'approved'
          and (v_campus_id is null or mb.campus_id = v_campus_id))
    ),
    'transcripts', jsonb_build_object(
      'pending', (select count(*) from public.transcript_requests tr
        where tr.institution_id = v_institution_id
          and tr.request_status in ('requested','authorized','generating')
          and (v_campus_id is null or tr.campus_id = v_campus_id)),
      'ready', (select count(*) from public.transcript_requests tr
        where tr.institution_id = v_institution_id
          and tr.request_status in ('ready','delivered')
          and (v_campus_id is null or tr.campus_id = v_campus_id))
    ),
    'operations', jsonb_build_object(
      'notification_backlog', (select count(*) from ops.notification_outbox no
        where no.institution_id = v_institution_id
          and no.job_status in ('pending','claimed')
          and (v_campus_id is null or no.campus_id = v_campus_id)),
      'open_incidents', (select count(*) from ops.incidents i
        where i.institution_id = v_institution_id
          and i.incident_status in ('open','acknowledged')
          and (v_campus_id is null or i.campus_id = v_campus_id))
    )
  ) into v_snapshot;

  return app.rpc_success(v_operation, v_correlation_id, null, v_snapshot);
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_claim_notifications(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'notification.claim';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_worker_id text := p_request#>>'{payload,worker_id}';
  v_limit integer := coalesce(nullif(p_request#>>'{payload,limit}','')::integer, 20);
  v_rows jsonb;
begin
  perform app.require_service();

  select coalesce(jsonb_agg(jsonb_build_object(
    'outbox_id', no.id,
    'institution_id', no.institution_id,
    'campus_id', no.campus_id,
    'channel', no.channel,
    'notification_type', no.notification_type,
    'recipient_address', no.recipient_address,
    'recipient_name', no.recipient_name,
    'subject', no.subject,
    'template_code', no.template_code,
    'payload', no.payload,
    'correlation_id', no.correlation_id,
    'attempt_number', no.attempt_count + 1,
    'max_attempts', no.max_attempts
  ) order by no.priority, no.created_at), '[]'::jsonb)
  into v_rows
  from ops.claim_notification_batch(v_worker_id, v_limit) no;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object('claimed_count', jsonb_array_length(v_rows), 'notifications', v_rows)
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_record_notification_attempt(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'notification.attempt.record';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_outbox_id uuid := nullif(p_request#>>'{payload,outbox_id}','')::uuid;
  v_status ops.delivery_status := nullif(p_request#>>'{payload,delivery_status}','')::ops.delivery_status;
  v_retryable boolean := coalesce((p_request#>>'{payload,retryable}')::boolean, false);
  v_outbox ops.notification_outbox%rowtype;
  v_attempt integer;
  v_next_job_status ops.job_status;
  v_delivery_id uuid;
begin
  perform app.require_service();

  select * into v_outbox
  from ops.notification_outbox no
  where no.id = v_outbox_id
  for update;

  if v_outbox.id is null then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_NOT_FOUND';
  end if;

  v_attempt := v_outbox.attempt_count + 1;

  if v_status = 'delivered' then
    v_next_job_status := 'completed';
  elsif v_retryable and v_attempt < v_outbox.max_attempts then
    v_next_job_status := 'pending';
  elsif v_status in ('permanent_failure','dead_letter') or v_attempt >= v_outbox.max_attempts then
    v_next_job_status := 'dead_letter';
  else
    v_next_job_status := 'failed';
  end if;

  insert into ops.notification_deliveries (
    institution_id, outbox_id, attempt_number, delivery_status,
    provider, provider_message_id, error_code, sanitized_error_message,
    retryable, finished_at
  )
  values (
    v_outbox.institution_id, v_outbox.id, v_attempt, v_status,
    coalesce(nullif(p_request#>>'{payload,provider}',''),'gmail'),
    nullif(p_request#>>'{payload,provider_message_id}',''),
    nullif(p_request#>>'{payload,error_code}',''),
    nullif(p_request#>>'{payload,error_message}',''),
    v_retryable, timezone('utc', now())
  )
  returning id into v_delivery_id;

  update ops.notification_outbox
  set attempt_count = v_attempt,
      job_status = v_next_job_status,
      available_at = case
        when v_next_job_status = 'pending'
          then timezone('utc', now()) + make_interval(mins => least(60, power(2, v_attempt)::integer))
        else available_at
      end,
      last_error_code = nullif(p_request#>>'{payload,error_code}',''),
      last_error_message = nullif(p_request#>>'{payload,error_message}',''),
      completed_at = case when v_next_job_status = 'completed' then timezone('utc', now()) else null end,
      claimed_at = null,
      claimed_by = null
  where id = v_outbox.id;

  update public.transcript_delivery_records tdr
  set delivery_status = v_status,
      provider_message_id = nullif(p_request#>>'{payload,provider_message_id}',''),
      delivered_at = case when v_status = 'delivered' then timezone('utc', now()) else null end
  where tdr.outbox_id = v_outbox.id;

  if v_status = 'delivered' then
    update public.transcript_requests tr
    set request_status = 'delivered'
    where exists (
      select 1 from public.transcript_delivery_records tdr
      where tdr.transcript_request_id = tr.id
        and tdr.outbox_id = v_outbox.id
    );
  end if;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'delivery_id', v_delivery_id,
      'outbox_id', v_outbox.id,
      'attempt_number', v_attempt,
      'job_status', v_next_job_status
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_get_operations_snapshot(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'operations.snapshot.get';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_snapshot jsonb;
begin
  if not app.is_service_request()
     and not app.can_administer_institution(v_institution_id)
     and not app.is_super_administrator() then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  select jsonb_build_object(
    'generated_at', timezone('utc', now()),
    'workflow_runs', jsonb_build_object(
      'started_last_24h', count(*) filter (
        where wr.started_at >= timezone('utc', now()) - interval '24 hours'
      ),
      'failed_last_24h', count(*) filter (
        where wr.started_at >= timezone('utc', now()) - interval '24 hours'
          and wr.run_status = 'failed'
      )
    ),
    'notifications', jsonb_build_object(
      'pending', (select count(*) from ops.notification_outbox no
        where (v_institution_id is null or no.institution_id = v_institution_id)
          and no.job_status = 'pending'),
      'claimed', (select count(*) from ops.notification_outbox no
        where (v_institution_id is null or no.institution_id = v_institution_id)
          and no.job_status = 'claimed'),
      'dead_letter', (select count(*) from ops.notification_outbox no
        where (v_institution_id is null or no.institution_id = v_institution_id)
          and no.job_status = 'dead_letter')
    ),
    'incidents', jsonb_build_object(
      'open', (select count(*) from ops.incidents i
        where (v_institution_id is null or i.institution_id = v_institution_id)
          and i.incident_status = 'open'),
      'acknowledged', (select count(*) from ops.incidents i
        where (v_institution_id is null or i.institution_id = v_institution_id)
          and i.incident_status = 'acknowledged')
    ),
    'reports', jsonb_build_object(
      'pending', (select count(*) from ops.hec_report_runs hr
        where (v_institution_id is null or hr.institution_id = v_institution_id)
          and hr.job_status in ('pending','claimed','running')),
      'failed', (select count(*) from ops.hec_report_runs hr
        where (v_institution_id is null or hr.institution_id = v_institution_id)
          and hr.job_status in ('failed','dead_letter'))
    )
  )
  into v_snapshot
  from ops.workflow_runs wr
  where v_institution_id is null or wr.institution_id = v_institution_id;

  return app.rpc_success(v_operation, v_correlation_id, null, v_snapshot);
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_apply_scheduled_maintenance(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'operations.maintenance.apply';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_released_claims integer := 0;
  v_dead_lettered integer := 0;
  v_stale_drafts integer := 0;
  v_run_id uuid;
begin
  perform app.require_service();

  update ops.notification_outbox
  set job_status = 'pending',
      claimed_at = null,
      claimed_by = null,
      available_at = timezone('utc', now())
  where job_status = 'claimed'
    and claimed_at < timezone('utc', now()) - interval '15 minutes'
    and attempt_count < max_attempts;
  get diagnostics v_released_claims = row_count;

  update ops.notification_outbox
  set job_status = 'dead_letter',
      completed_at = timezone('utc', now())
  where job_status in ('pending','claimed','failed')
    and attempt_count >= max_attempts;
  get diagnostics v_dead_lettered = row_count;

  update public.marks_batches
  set batch_status = 'superseded',
      finalized_at = coalesce(finalized_at, timezone('utc', now()))
  where batch_status = 'draft'
    and created_at < timezone('utc', now()) - interval '90 days';
  get diagnostics v_stale_drafts = row_count;

  insert into ops.maintenance_runs (
    operation, correlation_id, job_status, metrics, completed_at
  )
  values (
    v_operation, v_correlation_id, 'completed',
    jsonb_build_object(
      'released_notification_claims', v_released_claims,
      'dead_lettered_notifications', v_dead_lettered,
      'superseded_stale_marks_drafts', v_stale_drafts
    ),
    timezone('utc', now())
  )
  returning id into v_run_id;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'maintenance_run_id', v_run_id,
      'released_notification_claims', v_released_claims,
      'dead_lettered_notifications', v_dead_lettered,
      'superseded_stale_marks_drafts', v_stale_drafts
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_record_incident(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'incident.record';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_fingerprint text;
  v_incident_id uuid;
begin
  perform app.require_service();

  v_fingerprint := encode(
    extensions.digest(
      convert_to(
        concat_ws('|',
          coalesce(p_request#>>'{payload,workflow_code}',''),
          coalesce(p_request#>>'{payload,operation}',''),
          coalesce(p_request#>>'{payload,error_code}',''),
          coalesce(p_request#>>'{payload,error_location}','')
        ),
        'utf8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_incident_id := ops.upsert_incident(
    v_institution_id,
    v_campus_id,
    v_fingerprint,
    v_correlation_id,
    nullif(p_request#>>'{payload,workflow_code}',''),
    nullif(p_request#>>'{payload,operation}',''),
    coalesce(nullif(p_request#>>'{payload,severity}','')::ops.incident_severity, 'error'),
    coalesce(nullif(p_request#>>'{payload,title}',''), 'Workflow incident'),
    coalesce(nullif(p_request#>>'{payload,summary}',''), 'A workflow operation failed.'),
    coalesce(nullif(p_request#>>'{payload,event_type}',''), 'failure.observed'),
    coalesce(p_request#>'{payload,details}', '{}'::jsonb)
  );

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'incident_id', v_incident_id,
      'fingerprint', v_fingerprint,
      'deduplicated', (
        select i.occurrence_count > 1 from ops.incidents i where i.id = v_incident_id
      )
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_log_workflow_run(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'workflow.run.log';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_execution_id text := nullif(p_request#>>'{payload,n8n_execution_id}','');
  v_run_id uuid := nullif(p_request#>>'{payload,workflow_run_id}','')::uuid;
  v_status ops.workflow_run_status := coalesce(
    nullif(p_request#>>'{payload,run_status}','')::ops.workflow_run_status,
    'started'
  );
begin
  perform app.require_service();

  if v_run_id is null and v_execution_id is not null then
    select wr.id into v_run_id
    from ops.workflow_runs wr
    where wr.n8n_execution_id = v_execution_id
    for update;
  end if;

  if v_run_id is null then
    insert into ops.workflow_runs (
      institution_id, campus_id, workflow_code, n8n_execution_id,
      operation, correlation_id, idempotency_key, run_status,
      input_summary, output_summary, error_code, sanitized_error_message,
      finished_at
    )
    values (
      nullif(p_request->>'institution_id','')::uuid,
      nullif(p_request->>'campus_id','')::uuid,
      p_request#>>'{payload,workflow_code}',
      v_execution_id,
      nullif(p_request#>>'{payload,operation}',''),
      v_correlation_id,
      nullif(p_request->>'idempotency_key',''),
      v_status,
      coalesce(p_request#>'{payload,input_summary}', '{}'::jsonb),
      coalesce(p_request#>'{payload,output_summary}', '{}'::jsonb),
      nullif(p_request#>>'{payload,error_code}',''),
      nullif(p_request#>>'{payload,error_message}',''),
      case when v_status in ('completed','failed','cancelled')
        then timezone('utc', now()) else null end
    )
    returning id into v_run_id;
  else
    update ops.workflow_runs
    set run_status = v_status,
        output_summary = output_summary || coalesce(p_request#>'{payload,output_summary}', '{}'::jsonb),
        error_code = nullif(p_request#>>'{payload,error_code}',''),
        sanitized_error_message = nullif(p_request#>>'{payload,error_message}',''),
        finished_at = case when v_status in ('completed','failed','cancelled')
          then timezone('utc', now()) else finished_at end
    where id = v_run_id;
  end if;

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object('workflow_run_id', v_run_id, 'run_status', v_status)
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

do $do$
declare
  f text;
begin
  foreach f in array array[
    'rpc_submit_student_profile',
    'rpc_submit_enrollment_request',
    'rpc_decide_enrollment',
    'rpc_promote_waitlist',
    'rpc_submit_marks_batch',
    'rpc_finalize_marks_batch',
    'rpc_decide_marks_batch',
    'rpc_request_mark_correction',
    'rpc_decide_mark_correction',
    'rpc_publish_results',
    'rpc_create_transcript_request',
    'rpc_get_transcript_model',
    'rpc_record_transcript_document',
    'rpc_create_hec_report_run',
    'rpc_get_hec_enrollment_data',
    'rpc_record_generated_report',
    'rpc_search_students',
    'rpc_get_dashboard_snapshot',
    'rpc_claim_notifications',
    'rpc_record_notification_attempt',
    'rpc_get_operations_snapshot',
    'rpc_apply_scheduled_maintenance',
    'rpc_record_incident',
    'rpc_log_workflow_run'
  ]
  loop
    execute format('revoke all on function public.%I(jsonb) from public, anon, authenticated, service_role', f);
  end loop;
end
$do$;

grant execute on function public.rpc_submit_student_profile(jsonb) to service_role;
grant execute on function public.rpc_submit_enrollment_request(jsonb) to service_role;
grant execute on function public.rpc_record_transcript_document(jsonb) to service_role;
grant execute on function public.rpc_record_generated_report(jsonb) to service_role;
grant execute on function public.rpc_claim_notifications(jsonb) to service_role;
grant execute on function public.rpc_record_notification_attempt(jsonb) to service_role;
grant execute on function public.rpc_apply_scheduled_maintenance(jsonb) to service_role;
grant execute on function public.rpc_record_incident(jsonb) to service_role;
grant execute on function public.rpc_log_workflow_run(jsonb) to service_role;

grant execute on function public.rpc_decide_enrollment(jsonb) to authenticated;
grant execute on function public.rpc_decide_marks_batch(jsonb) to authenticated;
grant execute on function public.rpc_decide_mark_correction(jsonb) to authenticated;
grant execute on function public.rpc_publish_results(jsonb) to authenticated;
grant execute on function public.rpc_create_hec_report_run(jsonb) to authenticated;
grant execute on function public.rpc_search_students(jsonb) to authenticated;

grant execute on function public.rpc_promote_waitlist(jsonb) to authenticated, service_role;
grant execute on function public.rpc_submit_marks_batch(jsonb) to authenticated, service_role;
grant execute on function public.rpc_finalize_marks_batch(jsonb) to authenticated, service_role;
grant execute on function public.rpc_request_mark_correction(jsonb) to authenticated, service_role;
grant execute on function public.rpc_create_transcript_request(jsonb) to authenticated, service_role;
grant execute on function public.rpc_get_transcript_model(jsonb) to authenticated, service_role;
grant execute on function public.rpc_get_hec_enrollment_data(jsonb) to authenticated, service_role;
grant execute on function public.rpc_get_dashboard_snapshot(jsonb) to authenticated, service_role;
grant execute on function public.rpc_get_operations_snapshot(jsonb) to authenticated, service_role;

comment on function public.rpc_submit_student_profile(jsonb) is
  'Trusted-server idempotent student create/update RPC.';
comment on function public.rpc_submit_enrollment_request(jsonb) is
  'Trusted-server transactional enrollment evaluation and allocation RPC.';
comment on function public.rpc_submit_marks_batch(jsonb) is
  'Teacher/service marks draft submission and validation RPC.';
comment on function public.rpc_publish_results(jsonb) is
  'Authorized result publication, GPA and CGPA recalculation RPC.';
comment on function public.rpc_get_transcript_model(jsonb) is
  'Returns one complete transcript JSON model.';
comment on function public.rpc_get_dashboard_snapshot(jsonb) is
  'Returns one institution/campus-scoped operational dashboard object.';

commit;
