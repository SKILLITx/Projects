begin;

-- Workflow 05 repair:
-- The function uses an intentionally empty search_path. The prior implementation
-- called pgcrypto's gen_random_bytes() without a schema qualifier, which is not
-- resolvable from an empty search_path on the hosted Supabase database.
-- Generate the 12-character verification code from PostgreSQL's canonical UUID
-- generator instead, avoiding extension-schema dependence.

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
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
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
$function$;;

commit;
