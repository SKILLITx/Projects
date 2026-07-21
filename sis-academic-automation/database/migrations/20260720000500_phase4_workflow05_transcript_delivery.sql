begin;

create or replace function public.rpc_create_transcript_request(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_operation text := 'transcript.request.create';
  v_correlation_id uuid :=
    coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_idempotency_key text := nullif(btrim(p_request->>'idempotency_key'),'');
  v_student_id uuid := nullif(p_request#>>'{payload,student_id}','')::uuid;
  v_recipient_email text :=
    lower(btrim(coalesce(p_request#>>'{payload,recipient_email}','')));
  v_purpose text := nullif(btrim(p_request#>>'{payload,purpose}'),'');
  v_reference_prefix text;
  v_reference text;
  v_request public.transcript_requests%rowtype;
  v_document public.transcript_documents%rowtype;
  v_delivery public.transcript_delivery_records%rowtype;
  v_actor_staff_id uuid;
  v_authorized boolean := false;
  v_created boolean := false;
  v_response jsonb;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_REQUEST_OBJECT_REQUIRED';
  end if;

  if v_student_id is null
     or v_institution_id is null
     or v_campus_id is null
     or v_idempotency_key is null
     or position('@' in v_recipient_email) <= 1 then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_REQUEST_ENVELOPE_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.students s
    where s.id = v_student_id
      and s.institution_id = v_institution_id
      and s.campus_id = v_campus_id
      and s.status = 'active'::public.student_status
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSCRIPT_STUDENT_NOT_FOUND';
  end if;

  v_authorized :=
    app.is_service_request()
    or app.student_owns(v_student_id)
    or app.can_access_campus(v_institution_id, v_campus_id);

  if not v_authorized then
    raise exception using
      errcode = 'P0001',
      message = 'AUTH_SCOPE_DENIED';
  end if;

  if not exists (
    select 1
    from public.course_results cr
    where cr.institution_id = v_institution_id
      and cr.student_id = v_student_id
      and cr.result_status = 'published'::public.result_status
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSCRIPT_ACADEMIC_RECORD_MISSING';
  end if;

  select ts.reference_prefix
    into v_reference_prefix
  from public.transcript_settings ts
  where ts.institution_id = v_institution_id
    and ts.status = 'active'::public.record_status
    and ts.effective_from <= current_date
    and (ts.effective_to is null or ts.effective_to >= current_date)
  order by ts.version desc
  limit 1;

  if v_reference_prefix is null then
    raise exception using
      errcode = 'P0001',
      message = 'CONFIG_TRANSCRIPT_SETTINGS_MISSING';
  end if;

  select *
    into v_request
  from public.transcript_requests tr
  where tr.institution_id = v_institution_id
    and tr.idempotency_key = v_idempotency_key
  for update;

  if v_request.id is not null then
    if v_request.student_id <> v_student_id
       or v_request.campus_id <> v_campus_id
       or lower(v_request.recipient_email) <> v_recipient_email then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_PAYLOAD_CONFLICT';
    end if;
  else
    perform pg_advisory_xact_lock(
      hashtext(v_institution_id::text || ':transcript:' || extract(year from current_date)::text)
    );

    select *
      into v_request
    from public.transcript_requests tr
    where tr.institution_id = v_institution_id
      and tr.idempotency_key = v_idempotency_key
    for update;

    if v_request.id is null then
      v_reference :=
        v_reference_prefix || '-' ||
        to_char(current_date, 'YYYY') || '-' ||
        lpad(
          (
            select (count(*) + 1)::text
            from public.transcript_requests tr
            where tr.institution_id = v_institution_id
              and date_part('year', tr.created_at) =
                  date_part('year', timezone('utc', now()))
          ),
          6,
          '0'
        );

      insert into public.transcript_requests (
        institution_id,
        campus_id,
        student_id,
        requested_by_auth_user_id,
        recipient_email,
        purpose,
        correlation_id,
        idempotency_key,
        request_status,
        reference_number,
        verification_code,
        authorized_at
      )
      values (
        v_institution_id,
        v_campus_id,
        v_student_id,
        auth.uid(),
        v_recipient_email,
        v_purpose,
        v_correlation_id,
        v_idempotency_key,
        'authorized'::public.transcript_request_status,
        v_reference,
        upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 12)),
        timezone('utc', now())
      )
      returning * into v_request;

      v_created := true;
      v_actor_staff_id := app.current_staff_profile_id();

      insert into audit.audit_logs (
        institution_id,
        campus_id,
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
        v_actor_staff_id,
        v_operation,
        'transcript_request',
        v_request.id,
        v_correlation_id,
        'success',
        jsonb_build_object(
          'reference_number', v_request.reference_number,
          'student_id', v_student_id,
          'recipient_email', v_recipient_email
        )
      );
    else
      if v_request.student_id <> v_student_id
         or v_request.campus_id <> v_campus_id
         or lower(v_request.recipient_email) <> v_recipient_email then
        raise exception using
          errcode = 'P0001',
          message = 'IDEMPOTENCY_PAYLOAD_CONFLICT';
      end if;
    end if;
  end if;

  select *
    into v_document
  from public.transcript_documents td
  where td.institution_id = v_request.institution_id
    and td.transcript_request_id = v_request.id
  order by td.document_version desc, td.generated_at desc, td.id
  limit 1;

  if v_document.id is not null then
    select *
      into v_delivery
    from public.transcript_delivery_records tdr
    where tdr.institution_id = v_request.institution_id
      and tdr.transcript_request_id = v_request.id
      and tdr.transcript_document_id = v_document.id
      and lower(tdr.recipient_email) = lower(v_request.recipient_email)
    order by tdr.created_at desc, tdr.id
    limit 1;
  end if;

  v_response := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_strip_nulls(
      jsonb_build_object(
        'transcript_request_id', v_request.id,
        'reference_number', v_request.reference_number,
        'verification_code', v_request.verification_code,
        'status', v_request.request_status,
        'already_exists', not v_created,
        'document_reusable',
          (
            v_document.id is not null
            and v_document.pdf_drive_file_id is not null
            and v_document.pdf_file_url is not null
          ),
        'existing_document',
          case
            when v_document.id is null then null
            else jsonb_build_object(
              'transcript_document_id', v_document.id,
              'document_version', v_document.document_version,
              'google_doc_id', v_document.google_doc_id,
              'pdf_drive_file_id', v_document.pdf_drive_file_id,
              'pdf_file_url', v_document.pdf_file_url,
              'checksum_sha256', v_document.checksum_sha256,
              'generated_at', v_document.generated_at
            )
          end,
        'existing_delivery',
          case
            when v_delivery.id is null then null
            else jsonb_build_object(
              'delivery_record_id', v_delivery.id,
              'delivery_status', v_delivery.delivery_status,
              'provider_message_id', v_delivery.provider_message_id,
              'delivered_at', v_delivery.delivered_at
            )
          end
      )
    )
  );

  return v_response;
exception
  when others then
    return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;


create or replace function public.rpc_get_transcript_model(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_operation text := 'transcript.model.get';
  v_correlation_id uuid :=
    coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_request_id uuid :=
    nullif(p_request#>>'{payload,transcript_request_id}','')::uuid;
  v_request public.transcript_requests%rowtype;
  v_model jsonb;
begin
  if v_request_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_TRANSCRIPT_REQUEST_ID_REQUIRED';
  end if;

  select *
    into v_request
  from public.transcript_requests tr
  where tr.id = v_request_id;

  if v_request.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSCRIPT_REQUEST_NOT_FOUND';
  end if;

  if not app.is_service_request()
     and not app.student_owns(v_request.student_id)
     and not app.can_access_campus(v_request.institution_id, v_request.campus_id) then
    raise exception using
      errcode = 'P0001',
      message = 'AUTH_SCOPE_DENIED';
  end if;

  select jsonb_build_object(
    'transcript_request_id', v_request.id,
    'request_status', v_request.request_status,
    'reference_number', v_request.reference_number,
    'verification_code', v_request.verification_code,
    'issue_date', current_date,
    'recipient_email', v_request.recipient_email,
    'purpose', v_request.purpose,
    'request_correlation_id', v_request.correlation_id,
    'request_idempotency_key', v_request.idempotency_key,
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
    'terms', coalesce(
      (
        select jsonb_agg(term_model order by term_starts_on)
        from (
          select
            t.starts_on as term_starts_on,
            jsonb_build_object(
              'term_id', t.id,
              'term_code', t.code,
              'term_name', t.name,
              'academic_year', ay.name,
              'courses', coalesce(
                (
                  select jsonb_agg(
                    jsonb_build_object(
                      'course_code', course.code,
                      'course_title', course.title,
                      'credit_hours', cr.credit_hours,
                      'total_score', cr.total_score,
                      'letter_grade', cr.letter_grade,
                      'grade_point', cr.grade_point,
                      'outcome_code', cr.outcome_code
                    )
                    order by course.code
                  )
                  from public.course_results cr
                  join public.course_offerings co
                    on co.id = cr.course_offering_id
                   and co.institution_id = cr.institution_id
                  join public.courses course
                    on course.id = co.course_id
                   and course.institution_id = co.institution_id
                  where cr.institution_id = s.institution_id
                    and cr.student_id = s.id
                    and cr.term_id = t.id
                    and cr.result_status = 'published'::public.result_status
                ),
                '[]'::jsonb
              ),
              'semester_result',
                (
                  select jsonb_build_object(
                    'attempted_credits', sr.attempted_credits,
                    'earned_credits', sr.earned_credits,
                    'quality_points', sr.quality_points,
                    'gpa', sr.gpa,
                    'standing_code', sr.standing_code,
                    'at_risk', sr.at_risk
                  )
                  from public.semester_results sr
                  where sr.institution_id = s.institution_id
                    and sr.student_id = s.id
                    and sr.program_registration_id = spr.id
                    and sr.term_id = t.id
                    and sr.result_status = 'published'::public.result_status
                  order by sr.published_at desc nulls last, sr.calculated_at desc, sr.id
                  limit 1
                )
            ) as term_model
          from public.terms t
          join public.academic_years ay
            on ay.id = t.academic_year_id
           and ay.institution_id = t.institution_id
          where t.institution_id = s.institution_id
            and exists (
              select 1
              from public.course_results cr
              where cr.institution_id = s.institution_id
                and cr.student_id = s.id
                and cr.term_id = t.id
                and cr.result_status = 'published'::public.result_status
            )
        ) term_rows
      ),
      '[]'::jsonb
    ),
    'cumulative',
      (
        select jsonb_build_object(
          'attempted_credits', cr.attempted_credits,
          'earned_credits', cr.earned_credits,
          'quality_points', cr.quality_points,
          'cgpa', cr.cgpa,
          'standing_code', cr.standing_code,
          'at_risk', cr.at_risk,
          'calculated_at', cr.calculated_at
        )
        from public.cumulative_results cr
        where cr.institution_id = s.institution_id
          and cr.student_id = s.id
          and cr.program_registration_id = spr.id
        order by cr.calculated_at desc, cr.id
        limit 1
      ),
    'disclaimer',
      (
        select ts.disclaimer
        from public.transcript_settings ts
        where ts.institution_id = s.institution_id
          and ts.status = 'active'::public.record_status
          and ts.effective_from <= current_date
          and (ts.effective_to is null or ts.effective_to >= current_date)
        order by ts.version desc
        limit 1
      ),
    'template_configuration',
      (
        select ts.template_configuration
        from public.transcript_settings ts
        where ts.institution_id = s.institution_id
          and ts.status = 'active'::public.record_status
          and ts.effective_from <= current_date
          and (ts.effective_to is null or ts.effective_to >= current_date)
        order by ts.version desc
        limit 1
      ),
    'existing_document',
      (
        select jsonb_build_object(
          'transcript_document_id', td.id,
          'document_version', td.document_version,
          'google_doc_id', td.google_doc_id,
          'pdf_drive_file_id', td.pdf_drive_file_id,
          'pdf_file_url', td.pdf_file_url,
          'checksum_sha256', td.checksum_sha256,
          'generated_at', td.generated_at
        )
        from public.transcript_documents td
        where td.institution_id = v_request.institution_id
          and td.transcript_request_id = v_request.id
        order by td.document_version desc, td.generated_at desc, td.id
        limit 1
      ),
    'existing_delivery',
      (
        select jsonb_build_object(
          'delivery_record_id', tdr.id,
          'delivery_status', tdr.delivery_status,
          'provider_message_id', tdr.provider_message_id,
          'delivered_at', tdr.delivered_at
        )
        from public.transcript_delivery_records tdr
        where tdr.institution_id = v_request.institution_id
          and tdr.transcript_request_id = v_request.id
          and lower(tdr.recipient_email) = lower(v_request.recipient_email)
        order by tdr.created_at desc, tdr.id
        limit 1
      )
  )
    into v_model
  from public.students s
  join public.institutions i
    on i.id = s.institution_id
  join public.campuses c
    on c.id = s.campus_id
   and c.institution_id = s.institution_id
  join public.student_program_registrations spr
    on spr.student_id = s.id
   and spr.institution_id = s.institution_id
   and spr.registration_status = 'active'
  join public.programs p
    on p.id = spr.program_id
   and p.institution_id = spr.institution_id
  where s.id = v_request.student_id
    and s.institution_id = v_request.institution_id
    and s.campus_id = v_request.campus_id
  order by spr.created_at desc
  limit 1;

  if v_model is null
     or jsonb_array_length(coalesce(v_model->'terms', '[]'::jsonb)) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSCRIPT_ACADEMIC_RECORD_MISSING';
  end if;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    v_request.idempotency_key,
    v_model
  );
exception
  when others then
    return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;


create or replace function public.rpc_record_transcript_document(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_operation text := 'transcript.document.record';
  v_correlation_id uuid :=
    coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_request_id uuid :=
    nullif(p_request#>>'{payload,transcript_request_id}','')::uuid;
  v_google_doc_id text :=
    nullif(btrim(p_request#>>'{payload,google_doc_id}'),'');
  v_pdf_drive_file_id text :=
    nullif(btrim(p_request#>>'{payload,pdf_drive_file_id}'),'');
  v_pdf_file_url text :=
    nullif(btrim(p_request#>>'{payload,pdf_file_url}'),'');
  v_checksum text :=
    lower(nullif(btrim(p_request#>>'{payload,checksum_sha256}'),''));
  v_file_name text :=
    nullif(btrim(p_request#>>'{payload,file_name}'),'');
  v_request public.transcript_requests%rowtype;
  v_document public.transcript_documents%rowtype;
  v_outbox_id uuid;
  v_delivery_id uuid;
  v_version integer;
  v_already_recorded boolean := false;
begin
  perform app.require_service();

  if v_request_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_TRANSCRIPT_REQUEST_ID_REQUIRED';
  end if;

  if v_google_doc_id is null and v_pdf_drive_file_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_TRANSCRIPT_DOCUMENT_FILE_REQUIRED';
  end if;

  if v_checksum is not null and v_checksum !~ '^[a-f0-9]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'VALIDATION_TRANSCRIPT_CHECKSUM_INVALID';
  end if;

  select *
    into v_request
  from public.transcript_requests tr
  where tr.id = v_request_id
  for update;

  if v_request.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSCRIPT_REQUEST_NOT_FOUND';
  end if;

  if v_request.request_status = 'cancelled'::public.transcript_request_status then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSCRIPT_REQUEST_CANCELLED';
  end if;

  select *
    into v_document
  from public.transcript_documents td
  where td.institution_id = v_request.institution_id
    and td.transcript_request_id = v_request.id
  order by td.document_version desc, td.generated_at desc, td.id
  limit 1
  for update;

  if v_document.id is not null then
    if v_document.pdf_drive_file_id is not null
       and v_pdf_drive_file_id is not null
       and v_document.pdf_drive_file_id <> v_pdf_drive_file_id then
      raise exception using
        errcode = 'P0001',
        message = 'TRANSCRIPT_DOCUMENT_CONFLICT';
    end if;

    if v_document.checksum_sha256 is not null
       and v_checksum is not null
       and lower(v_document.checksum_sha256) <> v_checksum then
      raise exception using
        errcode = 'P0001',
        message = 'TRANSCRIPT_DOCUMENT_CONFLICT';
    end if;

    update public.transcript_documents
    set google_doc_id = coalesce(google_doc_id, v_google_doc_id),
        pdf_drive_file_id = coalesce(pdf_drive_file_id, v_pdf_drive_file_id),
        pdf_file_url = coalesce(pdf_file_url, v_pdf_file_url),
        checksum_sha256 = coalesce(checksum_sha256, v_checksum)
    where id = v_document.id
    returning * into v_document;

    v_already_recorded := true;
  else
    select coalesce(max(td.document_version), 0) + 1
      into v_version
    from public.transcript_documents td
    where td.transcript_request_id = v_request_id;

    insert into public.transcript_documents (
      institution_id,
      transcript_request_id,
      document_version,
      google_doc_id,
      pdf_drive_file_id,
      pdf_file_url,
      checksum_sha256
    )
    values (
      v_request.institution_id,
      v_request.id,
      v_version,
      v_google_doc_id,
      v_pdf_drive_file_id,
      v_pdf_file_url,
      v_checksum
    )
    returning * into v_document;
  end if;

  update public.transcript_requests
  set request_status = 'ready'::public.transcript_request_status,
      completed_at = coalesce(completed_at, timezone('utc', now())),
      error_code = null,
      sanitized_error_message = null,
      updated_at = timezone('utc', now())
  where id = v_request.id;

  insert into ops.notification_outbox (
    institution_id,
    campus_id,
    channel,
    notification_type,
    recipient_address,
    subject,
    template_code,
    payload,
    correlation_id,
    idempotency_key,
    job_status,
    priority
  )
  values (
    v_request.institution_id,
    v_request.campus_id,
    'email'::ops.notification_channel,
    'transcript.ready'::text,
    v_request.recipient_email,
    'Your transcript is ready',
    'transcript-ready',
    jsonb_strip_nulls(
      jsonb_build_object(
        'transcript_request_id', v_request.id,
        'transcript_document_id', v_document.id,
        'reference_number', v_request.reference_number,
        'verification_code', v_request.verification_code,
        'pdf_file_url', v_document.pdf_file_url,
        'pdf_drive_file_id', v_document.pdf_drive_file_id,
        'file_name', v_file_name
      )
    ),
    v_correlation_id,
    v_request.idempotency_key || ':transcript-ready',
    'pending'::ops.job_status,
    100
  )
  on conflict (
    institution_id,
    channel,
    notification_type,
    idempotency_key
  )
  do update
  set payload = excluded.payload,
      subject = excluded.subject,
      template_code = excluded.template_code,
      recipient_address = excluded.recipient_address,
      updated_at = timezone('utc', now())
  returning id into v_outbox_id;

  insert into public.transcript_delivery_records (
    institution_id,
    transcript_request_id,
    transcript_document_id,
    recipient_email,
    outbox_id,
    delivery_status
  )
  values (
    v_request.institution_id,
    v_request.id,
    v_document.id,
    v_request.recipient_email,
    v_outbox_id,
    'pending'::ops.delivery_status
  )
  on conflict do nothing;

  select tdr.id
    into v_delivery_id
  from public.transcript_delivery_records tdr
  where tdr.transcript_document_id = v_document.id
    and lower(tdr.recipient_email) = lower(v_request.recipient_email)
  limit 1;

  if not v_already_recorded then
    insert into audit.audit_logs (
      institution_id,
      campus_id,
      actor_staff_profile_id,
      operation,
      entity_type,
      entity_id,
      correlation_id,
      outcome,
      details
    )
    values (
      v_request.institution_id,
      v_request.campus_id,
      null,
      v_operation,
      'transcript_document',
      v_document.id,
      v_correlation_id,
      'success',
      jsonb_build_object(
        'transcript_request_id', v_request.id,
        'reference_number', v_request.reference_number,
        'pdf_drive_file_id', v_document.pdf_drive_file_id,
        'delivery_record_id', v_delivery_id,
        'outbox_id', v_outbox_id
      )
    );
  end if;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    v_request.idempotency_key,
    jsonb_build_object(
      'transcript_request_id', v_request.id,
      'transcript_document_id', v_document.id,
      'document_version', v_document.document_version,
      'delivery_record_id', v_delivery_id,
      'outbox_id', v_outbox_id,
      'status', 'ready',
      'already_recorded', v_already_recorded
    )
  );
exception
  when others then
    return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;


create or replace function public.rpc_mark_transcript_request_failed(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_operation text := 'transcript.request.fail';
  v_correlation_id uuid :=
    coalesce(nullif(p_request->>'correlation_id','')::uuid, gen_random_uuid());
  v_request_id uuid :=
    nullif(p_request#>>'{payload,transcript_request_id}','')::uuid;
  v_error_code text :=
    nullif(btrim(p_request#>>'{payload,error_code}'),'');
  v_error_message text :=
    nullif(btrim(p_request#>>'{payload,error_message}'),'');
  v_stage text :=
    nullif(btrim(p_request#>>'{payload,stage}'),'');
  v_request public.transcript_requests%rowtype;
begin
  perform app.require_service();

  if v_request_id is null then
    return app.rpc_success(
      v_operation,
      v_correlation_id,
      null,
      jsonb_build_object(
        'status', 'not_recorded',
        'reason', 'transcript_request_id_missing'
      )
    );
  end if;

  select *
    into v_request
  from public.transcript_requests tr
  where tr.id = v_request_id
  for update;

  if v_request.id is null then
    return app.rpc_success(
      v_operation,
      v_correlation_id,
      null,
      jsonb_build_object(
        'status', 'not_recorded',
        'reason', 'transcript_request_not_found'
      )
    );
  end if;

  if v_request.request_status not in (
    'ready'::public.transcript_request_status,
    'delivered'::public.transcript_request_status,
    'cancelled'::public.transcript_request_status
  ) then
    update public.transcript_requests
    set request_status = 'failed'::public.transcript_request_status,
        error_code = coalesce(v_error_code, 'TRANSCRIPT_EXTERNAL_FAILURE'),
        sanitized_error_message =
          coalesce(v_error_message, 'The transcript could not be completed.'),
        updated_at = timezone('utc', now())
    where id = v_request.id;

    insert into audit.audit_logs (
      institution_id,
      campus_id,
      actor_staff_profile_id,
      operation,
      entity_type,
      entity_id,
      correlation_id,
      outcome,
      details
    )
    values (
      v_request.institution_id,
      v_request.campus_id,
      null,
      v_operation,
      'transcript_request',
      v_request.id,
      v_correlation_id,
      'failure',
      jsonb_strip_nulls(
        jsonb_build_object(
          'error_code', v_error_code,
          'error_message', v_error_message,
          'stage', v_stage
        )
      )
    );
  end if;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    v_request.idempotency_key,
    jsonb_build_object(
      'transcript_request_id', v_request.id,
      'status',
        (
          select tr.request_status
          from public.transcript_requests tr
          where tr.id = v_request.id
        )
    )
  );
exception
  when others then
    return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;


create or replace function app.sync_transcript_delivery_from_notification()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_outbox ops.notification_outbox%rowtype;
begin
  select *
    into v_outbox
  from ops.notification_outbox no
  where no.id = new.outbox_id;

  if v_outbox.id is null
     or v_outbox.notification_type <> 'transcript.ready' then
    return new;
  end if;

  update public.transcript_delivery_records
  set delivery_status = new.delivery_status,
      provider_message_id =
        coalesce(new.provider_message_id, provider_message_id),
      delivered_at =
        case
          when new.delivery_status = 'delivered'::ops.delivery_status
            then coalesce(new.finished_at, timezone('utc', now()))
          else delivered_at
        end,
      updated_at = timezone('utc', now())
  where outbox_id = new.outbox_id;

  if new.delivery_status = 'delivered'::ops.delivery_status then
    update public.transcript_requests tr
    set request_status = 'delivered'::public.transcript_request_status,
        completed_at = coalesce(tr.completed_at, timezone('utc', now())),
        error_code = null,
        sanitized_error_message = null,
        updated_at = timezone('utc', now())
    where exists (
      select 1
      from public.transcript_delivery_records tdr
      where tdr.outbox_id = new.outbox_id
        and tdr.transcript_request_id = tr.id
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_sync_transcript_delivery_from_notification
  on ops.notification_deliveries;

create trigger trg_sync_transcript_delivery_from_notification
after insert or update of
  delivery_status,
  provider_message_id,
  finished_at
on ops.notification_deliveries
for each row
execute function app.sync_transcript_delivery_from_notification();


revoke all on function public.rpc_create_transcript_request(jsonb) from public;
revoke all on function public.rpc_get_transcript_model(jsonb) from public;
revoke all on function public.rpc_record_transcript_document(jsonb) from public;
revoke all on function public.rpc_mark_transcript_request_failed(jsonb) from public;

grant execute on function public.rpc_create_transcript_request(jsonb)
  to authenticated, service_role;
grant execute on function public.rpc_get_transcript_model(jsonb)
  to authenticated, service_role;
grant execute on function public.rpc_record_transcript_document(jsonb)
  to service_role;
grant execute on function public.rpc_mark_transcript_request_failed(jsonb)
  to service_role;

comment on function public.rpc_create_transcript_request(jsonb) is
  'Workflow 05: create/reuse an authorized transcript request with payload-safe idempotency.';
comment on function public.rpc_get_transcript_model(jsonb) is
  'Workflow 05: return one complete transcript model plus any existing artifact/delivery metadata.';
comment on function public.rpc_record_transcript_document(jsonb) is
  'Workflow 05: idempotently record Google Docs/PDF metadata and queue transcript-ready delivery.';
comment on function public.rpc_mark_transcript_request_failed(jsonb) is
  'Workflow 05: best-effort durable failure state for external document-generation errors.';
comment on function app.sync_transcript_delivery_from_notification() is
  'Synchronizes transcript delivery/request state from Workflow 08 notification delivery attempts.';

notify pgrst, 'reload schema';

commit;
