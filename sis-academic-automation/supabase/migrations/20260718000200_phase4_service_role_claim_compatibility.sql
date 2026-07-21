-- Fix service-role detection for real PostgREST requests.
--
-- The original helper read only request.jwt.claim.role. The deployed
-- PostgREST request exposes the JWT as request.jwt.claims JSON, so valid
-- service_role calls were rejected with AUTH_SERVICE_ROLE_REQUIRED.
--
-- Keep legacy claim compatibility for SQL tests and older gateways.

begin;

create or replace function app.is_service_request()
returns boolean
language sql
stable
security invoker
set search_path = pg_catalog
as $function$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (
      case
        when nullif(current_setting('request.jwt.claims', true), '') is null
          then null
        else (
          nullif(current_setting('request.jwt.claims', true), '')::jsonb
          ->> 'role'
        )
      end
    ),
    ''
  ) = 'service_role';
$function$;

comment on function app.is_service_request() is
  'Returns true for service_role requests using either the current PostgREST request.jwt.claims JSON setting or the legacy request.jwt.claim.role setting.';

revoke all on function app.is_service_request() from public, anon;
grant execute on function app.is_service_request() to authenticated, service_role;

commit;
