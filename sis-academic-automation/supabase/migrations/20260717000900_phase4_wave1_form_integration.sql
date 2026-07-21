-- Phase 4, Wave 1 database support:
-- code-resolving form RPCs and idempotent notification delivery attempts.
--
-- This migration does not modify any previously applied migration file.

begin;

create or replace function public.rpc_submit_student_profile_from_form(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'student.profile.form.submit';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_idempotency_key text := nullif(btrim(p_request->>'idempotency_key'), '');
  v_payload jsonb := coalesce(p_request->'payload', '{}'::jsonb);
  v_institution_id uuid;
  v_academic_model public.academic_model;
  v_campus_id uuid;
  v_program_id uuid;
  v_academic_year_id uuid;
  v_start_term_id uuid;
  v_student_id uuid;
  v_student_number text := nullif(btrim(v_payload->>'student_number'), '');
  v_existing_student_number text;
  v_full_name text := nullif(btrim(v_payload->>'full_name'), '');
  v_email text := nullif(lower(btrim(v_payload->>'primary_email')), '');
  v_identity_hash text;
  v_submission_mode text;
  v_match_count integer := 0;
  v_core_request jsonb;
  v_core_payload jsonb;
  v_core_documents jsonb := '[]'::jsonb;
  v_unclassified_links jsonb := '[]'::jsonb;
  v_document jsonb;
  v_requirement_id uuid;
  v_document_code text;
  v_document_url text;
  v_result jsonb;
  v_missing_documents jsonb := '[]'::jsonb;
  v_pending_documents jsonb := '[]'::jsonb;
  v_warnings jsonb;
begin
  perform app.require_service();

  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_OBJECT_REQUIRED';
  end if;

  if v_idempotency_key is null
     or v_full_name is null
     or v_email is null
     or nullif(btrim(v_payload->>'date_of_birth'), '') is null
     or nullif(btrim(v_payload->>'mobile_phone'), '') is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_STUDENT_REQUIRED_FIELDS';
  end if;

  if v_email is not null and position('@' in v_email) <= 1 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_EMAIL_INVALID';
  end if;

  select i.id, i.academic_model
    into v_institution_id, v_academic_model
  from public.institutions i
  where upper(i.code) = upper(btrim(v_payload->>'institution_code'))
    and i.status = 'active';

  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_INSTITUTION_NOT_FOUND';
  end if;

  select ir.result_payload
    into v_result
  from ops.idempotency_records ir
  where ir.institution_id = v_institution_id
    and ir.operation = 'student.profile.submit'
    and ir.idempotency_key = v_idempotency_key
    and ir.state = 'completed';

  if v_result is not null then
    return v_result;
  end if;

  if v_academic_model in ('subject_based','cambridge')
     and (
       nullif(btrim(v_payload->>'guardian_name'), '') is null
       or nullif(btrim(v_payload->>'guardian_phone'), '') is null
     ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_GUARDIAN_REQUIRED';
  end if;

  select c.id
    into v_campus_id
  from public.campuses c
  where c.institution_id = v_institution_id
    and upper(c.code) = upper(btrim(v_payload->>'campus_code'))
    and c.status = 'active';

  if v_campus_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_CAMPUS_NOT_FOUND';
  end if;

  select p.id
    into v_program_id
  from public.programs p
  where p.institution_id = v_institution_id
    and upper(p.code) = upper(btrim(v_payload->>'program_code'))
    and p.status = 'active';

  if v_program_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_PROGRAM_NOT_FOUND';
  end if;

  select ay.id
    into v_academic_year_id
  from public.academic_years ay
  where ay.institution_id = v_institution_id
    and upper(ay.code) = upper(btrim(v_payload->>'academic_year_code'))
    and ay.status = 'active';

  if v_academic_year_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_ACADEMIC_YEAR_NOT_FOUND';
  end if;

  select t.id
    into v_start_term_id
  from public.terms t
  where t.institution_id = v_institution_id
    and t.academic_year_id = v_academic_year_id
    and upper(t.code) = upper(btrim(v_payload->>'admission_term_code'))
    and t.status in ('active','draft');

  if v_start_term_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_TERM_NOT_FOUND';
  end if;

  if nullif(btrim(v_payload->>'identity_reference'), '') is not null then
    v_identity_hash := encode(
      extensions.digest(
        convert_to(lower(btrim(v_payload->>'identity_reference')), 'utf8'),
        'sha256'
      ),
      'hex'
    );
  end if;

  select
    count(*)::integer,
    (array_agg(s.id order by s.created_at, s.id))[1],
    (array_agg(s.student_number order by s.created_at, s.id))[1]
  into v_match_count, v_student_id, v_existing_student_number
  from public.students s
  where s.institution_id = v_institution_id
    and (
      (v_student_number is not null and upper(s.student_number) = upper(v_student_number))
      or (v_email is not null and lower(s.primary_email) = v_email)
      or (v_identity_hash is not null and s.cnic_hash = v_identity_hash)
    );

  if v_match_count > 1 then
    raise exception using errcode = 'P0001', message = 'STUDENT_DUPLICATE_CONFLICT';
  end if;

  if v_existing_student_number is not null
     and v_student_number is not null
     and upper(v_existing_student_number) <> upper(v_student_number) then
    raise exception using errcode = 'P0001', message = 'STUDENT_DUPLICATE_CONFLICT';
  end if;

  v_submission_mode := case
    when lower(coalesce(v_payload->>'submission_type','')) like 'update%' then 'update'
    else 'create'
  end;

  if v_submission_mode = 'update' and v_student_id is null then
    raise exception using errcode = 'P0001', message = 'STUDENT_NOT_FOUND';
  end if;

  if v_existing_student_number is not null then
    v_student_number := v_existing_student_number;
  elsif v_student_number is null then
    v_student_number := 'PENDING-' || upper(substr(
      encode(extensions.digest(convert_to(v_idempotency_key, 'utf8'), 'sha256'), 'hex'),
      1,
      12
    ));
  end if;

  if jsonb_typeof(v_payload->'documents') = 'array' then
    if exists (
      select 1
      from jsonb_array_elements(v_payload->'documents') as submitted(document)
      where nullif(upper(btrim(submitted.document->>'document_code')), '') is not null
      group by upper(btrim(submitted.document->>'document_code'))
      having count(*) > 1
    ) then
      raise exception using errcode = 'P0001', message = 'VALIDATION_DUPLICATE_DOCUMENT_CODE';
    end if;

    for v_document in select value from jsonb_array_elements(v_payload->'documents')
    loop
      v_document_code := nullif(upper(btrim(v_document->>'document_code')), '');
      v_document_url := nullif(btrim(v_document->>'url'), '');

      if v_document_code is null then
        if v_document_url is not null then
          v_unclassified_links := v_unclassified_links || jsonb_build_array(v_document_url);
        end if;
        continue;
      end if;

      select dr.id
        into v_requirement_id
      from public.document_requirements dr
      where dr.institution_id = v_institution_id
        and upper(dr.document_code) = v_document_code
        and dr.status = 'active'
        and (dr.program_id = v_program_id or dr.program_id is null)
      order by (dr.program_id = v_program_id) desc
      limit 1;

      if v_requirement_id is null then
        raise exception using errcode = 'P0001', message = 'VALIDATION_DOCUMENT_REQUIREMENT_INVALID';
      end if;

      if v_document_url is null then
        raise exception using errcode = 'P0001', message = 'VALIDATION_DOCUMENT_URL_REQUIRED';
      end if;

      v_core_documents := v_core_documents || jsonb_build_array(jsonb_build_object(
        'requirement_id', v_requirement_id,
        'file_name', coalesce(nullif(v_document->>'file_name',''), v_document_code),
        'storage_provider', 'google_drive',
        'storage_object_id', v_document_url,
        'document_status', 'submitted'
      ));
    end loop;
  end if;

  v_core_payload := jsonb_strip_nulls(jsonb_build_object(
    'student_number', v_student_number,
    'full_name', v_full_name,
    'date_of_birth', nullif(v_payload->>'date_of_birth',''),
    'cnic_hash', v_identity_hash,
    'primary_email', v_email,
    'status', 'active',
    'admitted_on', coalesce(nullif(v_payload->>'submitted_on',''), current_date::text),
    'program_id', v_program_id,
    'academic_year_id', v_academic_year_id,
    'start_term_id', v_start_term_id,
    'cohort_code', nullif(v_payload->>'cohort_code',''),
    'documents', v_core_documents,
    'metadata', jsonb_strip_nulls(jsonb_build_object(
      'gender', nullif(v_payload->>'gender',''),
      'mobile_phone', nullif(v_payload->>'mobile_phone',''),
      'guardian_name', nullif(v_payload->>'guardian_name',''),
      'guardian_phone', nullif(v_payload->>'guardian_phone',''),
      'previous_qualification', nullif(v_payload->>'previous_qualification',''),
      'additional_notes', nullif(v_payload->>'additional_notes',''),
      'submission_mode', v_submission_mode,
      'unclassified_document_links', v_unclassified_links,
      'source', 'google_forms'
    ))
  ));

  v_core_request := jsonb_build_object(
    'operation', 'student.profile.submit',
    'correlation_id', v_correlation_id,
    'idempotency_key', v_idempotency_key,
    'institution_id', v_institution_id,
    'campus_id', v_campus_id,
    'requester', coalesce(p_request->'requester', '{}'::jsonb),
    'submitted_at', p_request->>'submitted_at',
    'source', coalesce(p_request->'source', '{}'::jsonb),
    'payload', v_core_payload
  );

  v_result := public.rpc_submit_student_profile(v_core_request);

  if coalesce((v_result->>'success')::boolean, false) then
    v_student_id := nullif(v_result#>>'{data,student_id}','')::uuid;

    if nullif(btrim(v_payload->>'mobile_phone'), '') is not null then
      insert into public.student_contacts (
        institution_id, student_id, contact_type, contact_name, phone,
        is_primary, is_guardian, status
      ) values (
        v_institution_id, v_student_id, 'student_phone', v_full_name,
        btrim(v_payload->>'mobile_phone'), true, false, 'active'
      )
      on conflict (student_id, contact_type) where is_primary and status = 'active'
      do update set
        contact_name = excluded.contact_name,
        phone = excluded.phone,
        updated_at = timezone('utc', now());
    end if;

    if v_email is not null then
      insert into public.student_contacts (
        institution_id, student_id, contact_type, contact_name, email,
        is_primary, is_guardian, status
      ) values (
        v_institution_id, v_student_id, 'student_email', v_full_name,
        v_email, true, false, 'active'
      )
      on conflict (student_id, contact_type) where is_primary and status = 'active'
      do update set
        contact_name = excluded.contact_name,
        email = excluded.email,
        updated_at = timezone('utc', now());
    end if;

    if nullif(btrim(v_payload->>'guardian_phone'), '') is not null then
      insert into public.student_contacts (
        institution_id, student_id, contact_type, contact_name, phone,
        is_primary, is_guardian, status
      ) values (
        v_institution_id, v_student_id, 'guardian',
        nullif(btrim(v_payload->>'guardian_name'), ''),
        btrim(v_payload->>'guardian_phone'), true, true, 'active'
      )
      on conflict (student_id, contact_type) where is_primary and status = 'active'
      do update set
        contact_name = excluded.contact_name,
        phone = excluded.phone,
        is_guardian = true,
        updated_at = timezone('utc', now());
    end if;

    select coalesce(jsonb_agg(dr.document_code order by dr.document_code), '[]'::jsonb)
      into v_missing_documents
    from public.document_requirements dr
    where dr.institution_id = v_institution_id
      and dr.status = 'active'
      and dr.required_for_enrollment
      and (dr.program_id is null or dr.program_id = v_program_id)
      and not exists (
        select 1
        from public.student_documents sd
        where sd.student_id = v_student_id
          and sd.requirement_id = dr.id
          and sd.document_status in ('submitted','verified')
      );

    select coalesce(jsonb_agg(dr.document_code order by dr.document_code), '[]'::jsonb)
      into v_pending_documents
    from public.document_requirements dr
    where dr.institution_id = v_institution_id
      and dr.status = 'active'
      and dr.required_for_enrollment
      and (dr.program_id is null or dr.program_id = v_program_id)
      and exists (
        select 1
        from public.student_documents sd
        where sd.student_id = v_student_id
          and sd.requirement_id = dr.id
          and sd.document_status = 'submitted'
      )
      and not exists (
        select 1
        from public.student_documents sd
        where sd.student_id = v_student_id
          and sd.requirement_id = dr.id
          and sd.document_status = 'verified'
      );

    v_result := jsonb_set(v_result, '{data,missing_document_codes}', v_missing_documents, true);
    v_result := jsonb_set(v_result, '{data,pending_verification_document_codes}', v_pending_documents, true);

    v_warnings := coalesce(v_result->'warnings', '[]'::jsonb);
    if jsonb_array_length(v_missing_documents) > 0 then
      v_warnings := v_warnings || jsonb_build_array(
        'Some required enrollment documents have not been submitted.'
      );
    end if;
    if jsonb_array_length(v_pending_documents) > 0 then
      v_warnings := v_warnings || jsonb_build_array(
        'Some submitted documents still require staff verification.'
      );
    end if;
    v_result := jsonb_set(v_result, '{warnings}', v_warnings, true);

    update ops.idempotency_records
    set result_payload = v_result,
        updated_at = timezone('utc', now())
    where institution_id = v_institution_id
      and operation = 'student.profile.submit'
      and idempotency_key = v_idempotency_key
      and state = 'completed';
  end if;

  return v_result;
exception
  when others then
    return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_submit_enrollment_from_form(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'enrollment.form.submit';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_idempotency_key text := nullif(btrim(p_request->>'idempotency_key'), '');
  v_payload jsonb := coalesce(p_request->'payload', '{}'::jsonb);
  v_institution_id uuid;
  v_campus_id uuid;
  v_program_id uuid;
  v_term_id uuid;
  v_period_id uuid;
  v_student_id uuid;
  v_registration_id uuid;
  v_registration_count integer;
  v_course_code text;
  v_preferred_code text;
  v_offering_id uuid;
  v_offering_count integer;
  v_preferred_section_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_item jsonb;
  v_result_item jsonb;
  v_allow_fallback boolean := coalesce((v_payload->>'allow_fallback')::boolean, true);
  v_core_request jsonb;
  v_result jsonb;
  v_ordinal bigint;
begin
  perform app.require_service();

  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_OBJECT_REQUIRED';
  end if;

  if v_idempotency_key is null
     or nullif(btrim(v_payload->>'student_number'), '') is null
     or jsonb_typeof(v_payload->'course_codes') <> 'array'
     or jsonb_array_length(v_payload->'course_codes') = 0 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements_text(v_payload->'course_codes') as requested(value)
    group by upper(btrim(requested.value))
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_DUPLICATE_COURSE_CODE';
  end if;

  select i.id into v_institution_id
  from public.institutions i
  where upper(i.code) = upper(btrim(v_payload->>'institution_code'))
    and i.status = 'active';
  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_INSTITUTION_NOT_FOUND';
  end if;

  select ir.result_payload
    into v_result
  from ops.idempotency_records ir
  where ir.institution_id = v_institution_id
    and ir.operation = 'enrollment.submit'
    and ir.idempotency_key = v_idempotency_key
    and ir.state = 'completed';

  if v_result is not null then
    return v_result;
  end if;

  select c.id into v_campus_id
  from public.campuses c
  where c.institution_id = v_institution_id
    and upper(c.code) = upper(btrim(v_payload->>'campus_code'))
    and c.status = 'active';
  if v_campus_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_CAMPUS_NOT_FOUND';
  end if;

  select p.id into v_program_id
  from public.programs p
  where p.institution_id = v_institution_id
    and upper(p.code) = upper(btrim(v_payload->>'program_code'))
    and p.status = 'active';
  if v_program_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_PROGRAM_NOT_FOUND';
  end if;

  select t.id into v_term_id
  from public.terms t
  join public.academic_years ay on ay.id = t.academic_year_id
  where t.institution_id = v_institution_id
    and upper(t.code) = upper(btrim(v_payload->>'term_code'))
    and t.status = 'active'
    and ay.status = 'active'
  order by ay.starts_on desc, t.starts_on desc
  limit 1;
  if v_term_id is null then
    raise exception using errcode = 'P0001', message = 'CONFIG_TERM_NOT_FOUND';
  end if;

  select ep.id into v_period_id
  from public.enrollment_periods ep
  where ep.institution_id = v_institution_id
    and ep.term_id = v_term_id
    and (ep.campus_id is null or ep.campus_id = v_campus_id)
    and ep.status = 'active'
    and timezone('utc', now()) between ep.opens_at and ep.closes_at
  order by (ep.campus_id is not null) desc, ep.closes_at
  limit 1;
  if v_period_id is null then
    raise exception using errcode = 'P0001', message = 'ENROLLMENT_PERIOD_CLOSED';
  end if;

  select s.id into v_student_id
  from public.students s
  where s.institution_id = v_institution_id
    and s.campus_id = v_campus_id
    and upper(s.student_number) = upper(btrim(v_payload->>'student_number'))
    and s.status = 'active';
  if v_student_id is null then
    raise exception using errcode = 'P0001', message = 'STUDENT_NOT_ACTIVE';
  end if;

  select count(*)::integer,
         (array_agg(spr.id order by spr.created_at desc, spr.id))[1]
    into v_registration_count, v_registration_id
  from public.student_program_registrations spr
  where spr.student_id = v_student_id
    and spr.institution_id = v_institution_id
    and spr.campus_id = v_campus_id
    and spr.registration_status = 'active';

  if v_registration_count <> 1 then
    raise exception using errcode = 'P0001', message = 'CONFIG_ACTIVE_PROGRAM_REGISTRATION_AMBIGUOUS';
  end if;

  if not exists (
    select 1 from public.student_program_registrations spr
    where spr.id = v_registration_id and spr.program_id = v_program_id
  ) then
    raise exception using errcode = 'P0001', message = 'STUDENT_PROGRAM_MISMATCH';
  end if;

  for v_course_code, v_ordinal in
    select upper(btrim(value)), ordinality
    from jsonb_array_elements_text(v_payload->'course_codes') with ordinality
  loop
    if v_course_code = '' then
      raise exception using errcode = 'P0001', message = 'VALIDATION_COURSE_CODE_REQUIRED';
    end if;

    select count(*)::integer,
           (array_agg(co.id order by (co.program_id = v_program_id) desc, co.created_at, co.id))[1]
      into v_offering_count, v_offering_id
    from public.course_offerings co
    join public.courses c on c.id = co.course_id
    where co.institution_id = v_institution_id
      and co.campus_id = v_campus_id
      and co.term_id = v_term_id
      and co.status = 'open'
      and (co.program_id is null or co.program_id = v_program_id)
      and (upper(c.code) = v_course_code or upper(co.offering_code) = v_course_code);

    if v_offering_count = 0 then
      raise exception using errcode = 'P0001', message = 'ENROLLMENT_OFFERING_NOT_AVAILABLE';
    elsif v_offering_count > 1 then
      raise exception using errcode = 'P0001', message = 'CONFIG_COURSE_OFFERING_AMBIGUOUS';
    end if;

    v_preferred_code := nullif(upper(btrim(v_payload->'preferred_section_codes'->>((v_ordinal - 1)::integer))), '');
    v_preferred_section_id := null;

    if v_preferred_code is not null then
      select s.id into v_preferred_section_id
      from public.sections s
      where s.institution_id = v_institution_id
        and s.campus_id = v_campus_id
        and s.offering_id = v_offering_id
        and upper(s.code) = v_preferred_code
        and s.status = 'open';

      if v_preferred_section_id is null then
        raise exception using errcode = 'P0001', message = 'ENROLLMENT_PREFERRED_SECTION_NOT_FOUND';
      end if;
    elsif not v_allow_fallback then
      raise exception using errcode = 'P0001', message = 'VALIDATION_PREFERRED_SECTION_REQUIRED';
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'course_offering_id', v_offering_id,
      'preferred_section_id', v_preferred_section_id,
      'preference_order', v_ordinal
    ));
  end loop;

  v_core_request := jsonb_build_object(
    'operation', 'enrollment.submit',
    'correlation_id', v_correlation_id,
    'idempotency_key', v_idempotency_key,
    'institution_id', v_institution_id,
    'campus_id', v_campus_id,
    'requester', coalesce(p_request->'requester', '{}'::jsonb),
    'submitted_at', p_request->>'submitted_at',
    'source', coalesce(p_request->'source', '{}'::jsonb),
    'payload', jsonb_build_object(
      'student_id', v_student_id,
      'enrollment_period_id', v_period_id,
      'items', v_items,
      'request_notes', nullif(v_payload->>'request_notes','')
    )
  );

  v_result := public.rpc_submit_enrollment_request(v_core_request);

  if not v_allow_fallback and coalesce((v_result->>'success')::boolean, false) then
    for v_result_item in select value from jsonb_array_elements(v_result#>'{data,items}')
    loop
      if v_result_item->>'outcome' = 'enrolled' then
        select value into v_item
        from jsonb_array_elements(v_items)
        where value->>'course_offering_id' = v_result_item->>'course_offering_id'
        limit 1;

        if nullif(v_result_item->>'section_id','')::uuid
           is distinct from nullif(v_item->>'preferred_section_id','')::uuid then
          raise exception using errcode = 'P0001', message = 'ENROLLMENT_FALLBACK_NOT_ALLOWED';
        end if;
      end if;
    end loop;
  end if;

  return v_result;
exception
  when others then
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
  v_worker_id text := nullif(btrim(p_request#>>'{payload,worker_id}'), '');
  v_limit integer := coalesce(nullif(p_request#>>'{payload,limit}','')::integer, 20);
  v_rows jsonb;
  v_stale_dead_lettered integer := 0;
begin
  perform app.require_service();

  if v_worker_id is null then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_WORKER_REQUIRED';
  end if;

  with stale as (
    select no.id
    from ops.notification_outbox no
    where no.job_status = 'running'
      and no.claimed_at < timezone('utc', now()) - interval '15 minutes'
    for update
  ), closed_deliveries as (
    update ops.notification_deliveries nd
    set delivery_status = 'dead_letter',
        error_code = coalesce(nd.error_code, 'NOTIFICATION_DELIVERY_OUTCOME_UNKNOWN'),
        sanitized_error_message = coalesce(
          nd.sanitized_error_message,
          'The provider outcome could not be confirmed; automatic resend was blocked.'
        ),
        retryable = false,
        finished_at = coalesce(nd.finished_at, timezone('utc', now()))
    from stale s
    where nd.outbox_id = s.id
      and nd.delivery_status = 'sending'
    returning nd.outbox_id
  )
  update ops.notification_outbox no
  set job_status = 'dead_letter',
      last_error_code = 'NOTIFICATION_DELIVERY_OUTCOME_UNKNOWN',
      last_error_message = 'Provider outcome was uncertain; automatic resend was blocked.',
      completed_at = timezone('utc', now()),
      claimed_at = null,
      claimed_by = null,
      updated_at = timezone('utc', now())
  from stale s
  where no.id = s.id;
  get diagnostics v_stale_dead_lettered = row_count;

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
    'max_attempts', no.max_attempts,
    'worker_id', v_worker_id
  ) order by no.priority, no.created_at), '[]'::jsonb)
  into v_rows
  from ops.claim_notification_batch(v_worker_id, v_limit) no;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    null,
    jsonb_build_object(
      'claimed_count', jsonb_array_length(v_rows),
      'stale_uncertain_dead_lettered', v_stale_dead_lettered,
      'notifications', v_rows
    )
  );
exception
  when others then
    return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

create or replace function public.rpc_begin_notification_attempt(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'notification.attempt.begin';
  v_correlation_id uuid := coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_outbox_id uuid := nullif(p_request#>>'{payload,outbox_id}','')::uuid;
  v_worker_id text := nullif(btrim(p_request#>>'{payload,worker_id}'), '');
  v_attempt integer := nullif(p_request#>>'{payload,attempt_number}','')::integer;
  v_provider text := coalesce(nullif(p_request#>>'{payload,provider}',''), 'gmail');
  v_outbox ops.notification_outbox%rowtype;
  v_delivery ops.notification_deliveries%rowtype;
  v_delivery_id uuid;
  v_should_send boolean := false;
begin
  perform app.require_service();

  select * into v_outbox
  from ops.notification_outbox no
  where no.id = v_outbox_id
  for update;

  if v_outbox.id is null then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_NOT_FOUND';
  end if;

  if v_outbox.job_status = 'completed' then
    return app.rpc_success(
      v_operation,
      v_correlation_id,
      null,
      jsonb_build_object(
        'outbox_id', v_outbox.id,
        'should_send', false,
        'delivery_status', 'delivered',
        'job_status', v_outbox.job_status
      )
    );
  end if;

  if v_worker_id is null
     or v_outbox.claimed_by is distinct from v_worker_id
     or v_outbox.job_status not in ('claimed','running') then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_CLAIM_MISMATCH';
  end if;

  v_attempt := coalesce(v_attempt, v_outbox.attempt_count + 1);
  if v_attempt < 1 or v_attempt > v_outbox.max_attempts then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_ATTEMPT_INVALID';
  end if;

  select * into v_delivery
  from ops.notification_deliveries nd
  where nd.outbox_id = v_outbox.id
    and nd.attempt_number = v_attempt
  for update;

  if v_delivery.id is null then
    if v_attempt <> v_outbox.attempt_count + 1 then
      raise exception using errcode = 'P0001', message = 'NOTIFICATION_ATTEMPT_SEQUENCE_INVALID';
    end if;

    insert into ops.notification_deliveries (
      institution_id, outbox_id, attempt_number, delivery_status,
      provider, retryable
    ) values (
      v_outbox.institution_id, v_outbox.id, v_attempt, 'sending',
      v_provider, false
    ) returning id into v_delivery_id;

    update ops.notification_outbox
    set attempt_count = v_attempt,
        job_status = 'running',
        updated_at = timezone('utc', now())
    where id = v_outbox.id;

    v_should_send := true;
  else
    v_delivery_id := v_delivery.id;
    v_should_send := false;
  end if;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    null,
    jsonb_build_object(
      'delivery_id', v_delivery_id,
      'outbox_id', v_outbox.id,
      'attempt_number', v_attempt,
      'should_send', v_should_send,
      'delivery_status', coalesce(v_delivery.delivery_status, 'sending'::ops.delivery_status),
      'job_status', case when v_should_send then 'running' else v_outbox.job_status end
    )
  );
exception
  when others then
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
  v_attempt integer := nullif(p_request#>>'{payload,attempt_number}','')::integer;
  v_status ops.delivery_status := nullif(p_request#>>'{payload,delivery_status}','')::ops.delivery_status;
  v_retryable boolean := coalesce((p_request#>>'{payload,retryable}')::boolean, false);
  v_outbox ops.notification_outbox%rowtype;
  v_delivery ops.notification_deliveries%rowtype;
  v_next_job_status ops.job_status;
  v_delivery_id uuid;
begin
  perform app.require_service();

  if v_status is null or v_status = 'sending' then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_TERMINAL_STATUS_REQUIRED';
  end if;

  select * into v_outbox
  from ops.notification_outbox no
  where no.id = v_outbox_id
  for update;

  if v_outbox.id is null then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_NOT_FOUND';
  end if;

  v_attempt := coalesce(v_attempt, greatest(v_outbox.attempt_count, 1));

  select * into v_delivery
  from ops.notification_deliveries nd
  where nd.outbox_id = v_outbox.id
    and nd.attempt_number = v_attempt
  for update;

  if v_delivery.id is null then
    if v_attempt <> v_outbox.attempt_count + 1 and v_attempt <> v_outbox.attempt_count then
      raise exception using errcode = 'P0001', message = 'NOTIFICATION_ATTEMPT_SEQUENCE_INVALID';
    end if;

    insert into ops.notification_deliveries (
      institution_id, outbox_id, attempt_number, delivery_status,
      provider, provider_message_id, error_code, sanitized_error_message,
      retryable, finished_at
    ) values (
      v_outbox.institution_id, v_outbox.id, v_attempt, v_status,
      coalesce(nullif(p_request#>>'{payload,provider}',''), 'gmail'),
      nullif(p_request#>>'{payload,provider_message_id}',''),
      nullif(p_request#>>'{payload,error_code}',''),
      nullif(p_request#>>'{payload,error_message}',''),
      v_retryable, timezone('utc', now())
    ) returning id into v_delivery_id;
  else
    v_delivery_id := v_delivery.id;

    if v_delivery.delivery_status = 'delivered' then
      return app.rpc_success(
        v_operation,
        v_correlation_id,
        null,
        jsonb_build_object(
          'delivery_id', v_delivery.id,
          'outbox_id', v_outbox.id,
          'attempt_number', v_delivery.attempt_number,
          'job_status', 'completed',
          'idempotent_replay', true
        )
      );
    end if;

    update ops.notification_deliveries
    set delivery_status = v_status,
        provider = coalesce(nullif(p_request#>>'{payload,provider}',''), provider),
        provider_message_id = coalesce(
          nullif(p_request#>>'{payload,provider_message_id}',''), provider_message_id
        ),
        error_code = nullif(p_request#>>'{payload,error_code}',''),
        sanitized_error_message = nullif(p_request#>>'{payload,error_message}',''),
        retryable = v_retryable,
        finished_at = coalesce(finished_at, timezone('utc', now()))
    where id = v_delivery.id;
  end if;

  if v_status = 'delivered' then
    v_next_job_status := 'completed';
  elsif v_retryable and v_attempt < v_outbox.max_attempts then
    v_next_job_status := 'pending';
  elsif v_status in ('permanent_failure','dead_letter') or v_attempt >= v_outbox.max_attempts then
    v_next_job_status := 'dead_letter';
  else
    v_next_job_status := 'failed';
  end if;

  update ops.notification_outbox
  set attempt_count = greatest(attempt_count, v_attempt),
      job_status = v_next_job_status,
      available_at = case
        when v_next_job_status = 'pending'
          then timezone('utc', now()) + make_interval(mins => least(60, power(2, v_attempt)::integer))
        else available_at
      end,
      last_error_code = nullif(p_request#>>'{payload,error_code}',''),
      last_error_message = nullif(p_request#>>'{payload,error_message}',''),
      completed_at = case
        when v_next_job_status in ('completed','dead_letter') then timezone('utc', now())
        else null
      end,
      claimed_at = null,
      claimed_by = null,
      updated_at = timezone('utc', now())
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
    v_operation,
    v_correlation_id,
    null,
    jsonb_build_object(
      'delivery_id', v_delivery_id,
      'outbox_id', v_outbox.id,
      'attempt_number', v_attempt,
      'job_status', v_next_job_status,
      'idempotent_replay', false
    )
  );
exception
  when unique_violation then
    select nd.id into v_delivery_id
    from ops.notification_deliveries nd
    where nd.outbox_id = v_outbox_id and nd.attempt_number = v_attempt;

    return app.rpc_success(
      v_operation,
      v_correlation_id,
      null,
      jsonb_build_object(
        'delivery_id', v_delivery_id,
        'outbox_id', v_outbox_id,
        'attempt_number', v_attempt,
        'idempotent_replay', true
      )
    );
  when others then
    return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

revoke all on function public.rpc_submit_student_profile_from_form(jsonb)
  from public, anon, authenticated;
revoke all on function public.rpc_submit_enrollment_from_form(jsonb)
  from public, anon, authenticated;
revoke all on function public.rpc_begin_notification_attempt(jsonb)
  from public, anon, authenticated;

revoke all on function public.rpc_claim_notifications(jsonb)
  from public, anon, authenticated;
revoke all on function public.rpc_record_notification_attempt(jsonb)
  from public, anon, authenticated;

grant execute on function public.rpc_submit_student_profile_from_form(jsonb) to service_role;
grant execute on function public.rpc_submit_enrollment_from_form(jsonb) to service_role;
grant execute on function public.rpc_begin_notification_attempt(jsonb) to service_role;
grant execute on function public.rpc_claim_notifications(jsonb) to service_role;
grant execute on function public.rpc_record_notification_attempt(jsonb) to service_role;

comment on function public.rpc_submit_student_profile_from_form(jsonb) is
  'Resolve institution, campus and academic codes from a normalized Google Form request, then invoke the idempotent student-profile RPC.';
comment on function public.rpc_submit_enrollment_from_form(jsonb) is
  'Resolve form codes to tenant-scoped enrollment identifiers and invoke the transactional enrollment RPC.';
comment on function public.rpc_begin_notification_attempt(jsonb) is
  'Reserve one provider delivery attempt before sending so retries cannot silently duplicate an external notification.';
comment on function public.rpc_claim_notifications(jsonb) is
  'Claim pending notifications and dead-letter stale delivery attempts whose external outcome is uncertain.';
comment on function public.rpc_record_notification_attempt(jsonb) is
  'Idempotently finalize a previously reserved notification delivery attempt.';

commit;
