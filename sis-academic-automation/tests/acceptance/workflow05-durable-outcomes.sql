with target_student as (
  select s.id, s.institution_id, s.campus_id, s.student_number
  from public.students s
  where upper(s.student_number) = 'DMU-0001'
  order by s.created_at
  limit 1
),
target_request as (
  select tr.*
  from public.transcript_requests tr
  join target_student s
    on s.id = tr.student_id
   and s.institution_id = tr.institution_id
  where lower(tr.recipient_email) = lower('zaidrizwan.278@gmail.com')
  order by tr.created_at desc, tr.id
  limit 1
),
target_document as (
  select td.*
  from public.transcript_documents td
  join target_request tr
    on tr.id = td.transcript_request_id
   and tr.institution_id = td.institution_id
  order by td.document_version desc, td.generated_at desc, td.id
  limit 1
),
target_delivery as (
  select tdr.*
  from public.transcript_delivery_records tdr
  join target_request tr
    on tr.id = tdr.transcript_request_id
   and tr.institution_id = tdr.institution_id
  join target_document td
    on td.id = tdr.transcript_document_id
  order by tdr.created_at desc, tdr.id
  limit 1
),
target_outbox as (
  select no.*
  from ops.notification_outbox no
  join target_delivery tdr on tdr.outbox_id = no.id
  limit 1
),
latest_attempt as (
  select nd.*
  from ops.notification_deliveries nd
  join target_outbox no on no.id = nd.outbox_id
  order by nd.attempt_number desc, nd.created_at desc, nd.id
  limit 1
),
duplicate_counts as (
  select
    (select count(*) from public.transcript_documents td
      join target_request tr on tr.id = td.transcript_request_id)
      as document_count,
    (select count(*) from public.transcript_delivery_records tdr
      join target_request tr on tr.id = tdr.transcript_request_id)
      as delivery_count,
    (select count(*) from ops.notification_outbox no
      join target_request tr
        on no.idempotency_key = tr.idempotency_key || ':transcript-ready'
       and no.institution_id = tr.institution_id)
      as outbox_count
)
select jsonb_build_object(
  'status',
    case
      when (select id from target_request) is not null
       and (select request_status::text from target_request)
            in ('ready', 'delivered')
       and (select id from target_document) is not null
       and nullif((select google_doc_id from target_document), '') is not null
       and nullif((select pdf_drive_file_id from target_document), '') is not null
       and nullif((select pdf_file_url from target_document), '') is not null
       and (select checksum_sha256 from target_document)
            ~ '^[A-Fa-f0-9]{64}$'
       and (select id from target_delivery) is not null
       and (select id from target_outbox) is not null
       and (select document_count from duplicate_counts) = 1
       and (select delivery_count from duplicate_counts) = 1
       and (select outbox_count from duplicate_counts) = 1
      then 'PASS'
      else 'FAIL'
    end,
  'request',
    (
      select jsonb_build_object(
        'transcript_request_id', tr.id,
        'reference_number', tr.reference_number,
        'verification_code', tr.verification_code,
        'recipient_email', tr.recipient_email,
        'request_status', tr.request_status,
        'correlation_id', tr.correlation_id,
        'idempotency_key', tr.idempotency_key,
        'authorized_at', tr.authorized_at,
        'completed_at', tr.completed_at
      )
      from target_request tr
    ),
  'document',
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
      from target_document td
    ),
  'delivery',
    (
      select jsonb_build_object(
        'delivery_record_id', tdr.id,
        'delivery_status', tdr.delivery_status,
        'provider_message_id', tdr.provider_message_id,
        'delivered_at', tdr.delivered_at,
        'outbox_id', tdr.outbox_id
      )
      from target_delivery tdr
    ),
  'outbox',
    (
      select jsonb_build_object(
        'outbox_id', no.id,
        'notification_type', no.notification_type,
        'recipient_address', no.recipient_address,
        'job_status', no.job_status,
        'attempt_count', no.attempt_count,
        'completed_at', no.completed_at,
        'payload', no.payload
      )
      from target_outbox no
    ),
  'latest_notification_attempt',
    (
      select jsonb_build_object(
        'delivery_status', nd.delivery_status,
        'provider', nd.provider,
        'provider_message_id', nd.provider_message_id,
        'attempt_number', nd.attempt_number,
        'retryable', nd.retryable,
        'finished_at', nd.finished_at
      )
      from latest_attempt nd
    ),
  'idempotency_counts',
    (select to_jsonb(duplicate_counts) from duplicate_counts)
) as workflow05_durable_outcomes;
