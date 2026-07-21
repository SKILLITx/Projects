with target as (
  select
    p.oid,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_create_transcript_request'
    and pg_get_function_identity_arguments(p.oid) = 'p_request jsonb'
  limit 1
)
select jsonb_build_object(
  'status',
    case
      when exists (select 1 from target)
       and (select definition from target) like
         '%replace(gen_random_uuid()::text, ''-'', '''')%'
       and (select definition from target) not like
         '%gen_random_bytes(%'
      then 'PASS'
      else 'FAIL'
    end,
  'checks',
    jsonb_build_object(
      'request_rpc_exists', exists(select 1 from target),
      'uuid_based_verification_code',
        coalesce(
          (select definition from target) like
            '%replace(gen_random_uuid()::text, ''-'', '''')%',
          false
        ),
      'unqualified_pgcrypto_call_removed',
        coalesce(
          (select definition from target) not like '%gen_random_bytes(%',
          false
        ),
      'empty_search_path_preserved',
        coalesce(
          (select definition from target) like '%SET search_path TO ''''%',
          false
        )
    )
) as workflow05_verification_code_fix;
