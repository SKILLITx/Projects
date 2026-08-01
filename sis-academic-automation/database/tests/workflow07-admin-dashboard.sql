-- Workflow 07 database acceptance suite.
-- Runs inside one transaction and rolls back temporary role changes.
-- It does not print raw identity values, tokens, or personal data.

begin;

do $test$
declare
  v_actor uuid;
  v_staff uuid;
  v_dmu uuid;
  v_isb uuid;
  v_other_institution uuid;
  v_result jsonb;
  v_dashboard jsonb;
  v_original_super_status public.assignment_status;
begin
  select sp.auth_user_id, sp.id
  into v_actor, v_staff
  from public.staff_profiles sp
  where lower(sp.email) = lower('zaidrizwan.278@gmail.com')
    and sp.status = 'active'
  limit 1;

  if v_actor is null then
    raise exception 'WORKFLOW07_TEST_ACTOR_MISSING';
  end if;

  select i.id into v_dmu from public.institutions i where i.code='DMU' limit 1;
  select c.id into v_isb from public.campuses c where c.institution_id=v_dmu and c.code='ISB' limit 1;
  select i.id into v_other_institution from public.institutions i where i.id<>v_dmu order by i.code limit 1;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_result := public.rpc_search_students(jsonb_build_object(
    'operation','student.search',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow07:student-number',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',v_dmu,'campus_id',v_isb),
    'payload',jsonb_build_object('query','DMU-0001','search_type','student_number','limit',25,'offset',0)
  ));
  if v_result->>'success' <> 'true' or v_result#>>'{data,count}' <> '1' then
    raise exception 'WORKFLOW07_STUDENT_NUMBER_SEARCH_FAILED';
  end if;

  v_result := public.rpc_search_students(jsonb_build_object(
    'operation','student.search',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow07:identity',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',v_dmu,'campus_id',v_isb),
    'payload',jsonb_build_object('query','DEMO-ID-DMU-0001','search_type','identity_reference','limit',25,'offset',0)
  ));
  if v_result->>'success' <> 'true'
     or v_result#>>'{data,students,0,identity_reference_masked}' not like '%0001'
     or v_result::text like '%DEMO-ID-DMU-0001%' then
    raise exception 'WORKFLOW07_IDENTITY_MASKING_FAILED';
  end if;

  v_result := public.rpc_search_students(jsonb_build_object(
    'operation','student.search',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow07:zero',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',v_dmu,'campus_id',v_isb),
    'payload',jsonb_build_object('query','NO-SUCH-STUDENT-999999','search_type','student_number','limit',25,'offset',0)
  ));
  if v_result->>'success' <> 'true'
     or v_result#>>'{data,count}' <> '0'
     or jsonb_array_length(v_result#>'{data,students}') <> 0 then
    raise exception 'WORKFLOW07_ZERO_RESULT_SHAPE_FAILED';
  end if;

  v_dashboard := public.rpc_get_dashboard_snapshot(jsonb_build_object(
    'operation','dashboard.snapshot',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow07:dashboard',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',v_dmu,'campus_id',v_isb),
    'payload',jsonb_build_object('term_id',null)
  ));
  if v_dashboard->>'success' <> 'true'
     or jsonb_typeof(v_dashboard#>'{data,metrics}') <> 'object'
     or jsonb_typeof(v_dashboard#>'{data,grade_distribution}') <> 'array'
     or jsonb_typeof(v_dashboard#>'{data,course_capacity}') <> 'array'
     or v_dashboard#>'{data,metrics,students_total}' is null then
    raise exception 'WORKFLOW07_DASHBOARD_SHAPE_FAILED';
  end if;

  -- Prove that a teacher-only actor is denied. All changes roll back.
  update public.role_assignments
  set status='suspended'
  where staff_profile_id=v_staff and role<>'teacher' and status='active';

  v_result := public.rpc_search_students(jsonb_build_object(
    'operation','student.search',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow07:teacher-denial',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',v_dmu,'campus_id',v_isb),
    'payload',jsonb_build_object('query','DMU-0001','search_type','student_number','limit',25,'offset',0)
  ));
  if v_result->>'success' <> 'false' or v_result#>>'{error,code}' <> 'AUTH_SCOPE_DENIED' then
    raise exception 'WORKFLOW07_TEACHER_ONLY_DENIAL_FAILED';
  end if;

  -- Restore current roles inside the still-rollback-only transaction.
  update public.role_assignments
  set status='active'
  where staff_profile_id=v_staff and role<>'teacher' and status='suspended';
end;
$test$;

select jsonb_pretty(jsonb_build_object(
  'status','PASS',
  'suite','workflow07-admin-dashboard',
  'checks',jsonb_build_array(
    'student-number search',
    'exact identity hash and masked output',
    'zero-result stable shape',
    'dashboard zero-safe shape',
    'teacher-only denial'
  ),
  'rolled_back',true
)) as workflow07_database_tests;

rollback;
