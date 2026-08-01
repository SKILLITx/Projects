begin;

select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","sub":"00000000-0000-0000-0000-000000000000"}', true);

do $test$
begin
  if not app.is_service_request() then
    raise exception 'CURRENT_POSTGREST_SERVICE_ROLE_CLAIM_NOT_RECOGNIZED';
  end if;
end;
$test$;

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);

do $test$
begin
  if app.is_service_request() then
    raise exception 'AUTHENTICATED_ROLE_WAS_INCORRECTLY_ACCEPTED';
  end if;
end;
$test$;

select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.role', 'service_role', true);

do $test$
begin
  if not app.is_service_request() then
    raise exception 'LEGACY_SERVICE_ROLE_CLAIM_NOT_RECOGNIZED';
  end if;
end;
$test$;

select jsonb_build_object(
  'suite', 'phase4-service-role-claim-compatibility',
  'success', true,
  'current_postgrest_claims_supported', true,
  'legacy_claim_supported', true,
  'authenticated_claim_rejected', true
) as result;

rollback;
