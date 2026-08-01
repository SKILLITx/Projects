with checks as (
  select
    to_regprocedure('public.rpc_create_transcript_request(jsonb)') is not null
      as request_rpc_exists,
    to_regprocedure('public.rpc_get_transcript_model(jsonb)') is not null
      as model_rpc_exists,
    to_regprocedure('public.rpc_record_transcript_document(jsonb)') is not null
      as record_rpc_exists,
    to_regprocedure('public.rpc_mark_transcript_request_failed(jsonb)') is not null
      as failure_rpc_exists,
    exists (
      select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'ops'
        and c.relname = 'notification_deliveries'
        and t.tgname = 'trg_sync_transcript_delivery_from_notification'
        and not t.tgisinternal
    ) as delivery_sync_trigger_exists,
    has_function_privilege(
      'authenticated',
      'public.rpc_create_transcript_request(jsonb)',
      'EXECUTE'
    ) as authenticated_can_request,
    has_function_privilege(
      'authenticated',
      'public.rpc_get_transcript_model(jsonb)',
      'EXECUTE'
    ) as authenticated_can_get_model,
    has_function_privilege(
      'service_role',
      'public.rpc_record_transcript_document(jsonb)',
      'EXECUTE'
    ) as service_can_record,
    not has_function_privilege(
      'authenticated',
      'public.rpc_record_transcript_document(jsonb)',
      'EXECUTE'
    ) as authenticated_cannot_record,
    position(
      'IDEMPOTENCY_PAYLOAD_CONFLICT'
      in pg_get_functiondef(
        'public.rpc_create_transcript_request(jsonb)'::regprocedure
      )
    ) > 0 as payload_safe_idempotency,
    position(
      '''email''::ops.notification_channel'
      in pg_get_functiondef(
        'public.rpc_record_transcript_document(jsonb)'::regprocedure
      )
    ) > 0 as explicit_notification_enum_cast,
    position(
      'already_recorded'
      in pg_get_functiondef(
        'public.rpc_record_transcript_document(jsonb)'::regprocedure
      )
    ) > 0 as document_reuse_contract
)
select jsonb_build_object(
  'status',
    case
      when request_rpc_exists
       and model_rpc_exists
       and record_rpc_exists
       and failure_rpc_exists
       and delivery_sync_trigger_exists
       and authenticated_can_request
       and authenticated_can_get_model
       and service_can_record
       and authenticated_cannot_record
       and payload_safe_idempotency
       and explicit_notification_enum_cast
       and document_reuse_contract
      then 'PASS'
      else 'FAIL'
    end,
  'checks',
    to_jsonb(checks)
) as workflow05_hosted_verification
from checks;
