select jsonb_build_object(
  'status',
  case
    when pg_get_functiondef(
      'public.rpc_publish_results(jsonb)'::regprocedure
    ) like '%''email''::ops.notification_channel%'
    and pg_get_functiondef(
      'public.rpc_publish_results(jsonb)'::regprocedure
    ) like '%''success''%'
    and pg_get_functiondef(
      'public.rpc_publish_results(jsonb)'::regprocedure
    ) not like '%v_correlation_id,%''completed''%'
    then 'PASS'
    else 'FAIL'
  end,
  'channel_cast_present',
    pg_get_functiondef(
      'public.rpc_publish_results(jsonb)'::regprocedure
    ) like '%''email''::ops.notification_channel%',
  'valid_audit_outcome_present',
    pg_get_functiondef(
      'public.rpc_publish_results(jsonb)'::regprocedure
    ) like '%''success''%',
  'invalid_completed_audit_outcome_present',
    pg_get_functiondef(
      'public.rpc_publish_results(jsonb)'::regprocedure
    ) like '%v_correlation_id,%''completed''%'
) as workflow04_publication_notification_enum_fix;
