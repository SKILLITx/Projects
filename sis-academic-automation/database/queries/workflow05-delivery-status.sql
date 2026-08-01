with target_request as (
  select tr.*
  from public.transcript_requests tr
  where tr.idempotency_key = 'portal:transcript.request:workflow05-pilot-01'
  order by tr.created_at desc
  limit 1
),
target_document as (
  select td.*
  from public.transcript_documents td
  join target_request tr on tr.id = td.transcript_request_id
  order by td.document_version desc, td.generated_at desc nulls last, td.created_at desc
  limit 1
),
target_delivery as (
  select tdr.*
  from public.transcript_delivery_records tdr
  join target_request tr on tr.id = tdr.transcript_request_id
  order by tdr.created_at desc
  limit 1
),
target_outbox as (
  select no.*
  from ops.notification_outbox no
  where no.id = (select outbox_id from target_delivery)
     or (
       no.idempotency_key =
         'portal:transcript.request:workflow05-pilot-01:transcript-ready'
     )
  order by no.created_at desc
  limit 1
)
select jsonb_build_object(
  'status',
    case
      when not exists(select 1 from target_request) then 'REQUEST_NOT_FOUND'
      when not exists(select 1 from target_document) then 'DOCUMENT_NOT_RECORDED'
      when not exists(select 1 from target_outbox) then 'NOTIFICATION_NOT_QUEUED'
      when (select job_status::text from target_outbox) = 'completed'
        then 'NOTIFICATION_COMPLETED'
      when (select job_status::text from target_outbox) in ('failed','dead_letter')
        then 'NOTIFICATION_FAILED'
      else 'NOTIFICATION_PENDING'
    end,
  'request',
    coalesce((select to_jsonb(tr) from target_request tr), '{}'::jsonb),
  'document',
    coalesce((select to_jsonb(td) from target_document td), '{}'::jsonb),
  'delivery_record',
    coalesce((select to_jsonb(tdr) from target_delivery tdr), '{}'::jsonb),
  'outbox',
    coalesce((select to_jsonb(no) from target_outbox no), '{}'::jsonb),
  'delivery_attempts',
    coalesce(
      (
        select jsonb_agg(to_jsonb(nd) order by nd.created_at)
        from ops.notification_deliveries nd
        where nd.outbox_id = (select id from target_outbox)
      ),
      '[]'::jsonb
    )
) as workflow05_delivery_status;
