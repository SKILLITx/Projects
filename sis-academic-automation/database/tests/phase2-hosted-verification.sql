-- Phase 2 hosted Supabase verification suite.
-- Run only after migrations 003 through 008 are applied.
-- The mutating RPC test is enclosed in a transaction and rolled back.

-- 1. Catalog, RLS, migration and seed assertions.
do $verify$
declare
  v_count integer;
  v_bad integer;
  v_grade jsonb;
  v_expected_migrations text[] := array[
    '20260717000100','20260717000200','20260717000300','20260717000400',
    '20260717000500','20260717000600','20260717000700','20260717000800'
  ];
begin
  select count(*) into v_count
  from supabase_migrations.schema_migrations
  where version = any(v_expected_migrations);
  if v_count <> 8 then raise exception 'PHASE2_MIGRATION_HISTORY_MISMATCH: expected 8, found %', v_count; end if;

  select count(*) into v_count
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r';
  if v_count <> 56 then raise exception 'PHASE2_PUBLIC_TABLE_COUNT_MISMATCH: expected 56, found %', v_count; end if;

  select count(*) into v_bad
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
  if v_bad <> 0 then raise exception 'PHASE2_RLS_DISABLED_TABLES: %', v_bad; end if;

  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname like 'rpc_%'
    and p.prorettype='jsonb'::regtype and p.pronargs=1
    and p.proargtypes[0]='jsonb'::regtype and p.prosecdef
    and 'search_path=""' = any(coalesce(p.proconfig,array[]::text[]));
  if v_count <> 24 then raise exception 'PHASE2_RPC_CONTRACT_MISMATCH: expected 24, found %', v_count; end if;

  select count(*) into v_bad
  from information_schema.role_table_grants
  where table_schema='public' and grantee='anon';
  if v_bad <> 0 then raise exception 'PHASE2_ANON_TABLE_GRANTS_FOUND: %', v_bad; end if;

  select count(*) into v_bad
  from information_schema.routine_privileges
  where routine_schema='public' and grantee='anon' and routine_name like 'rpc_%';
  if v_bad <> 0 then raise exception 'PHASE2_ANON_RPC_GRANTS_FOUND: %', v_bad; end if;

  if (select count(*) from public.institutions) <> 2 then raise exception 'SEED_INSTITUTIONS_MISMATCH'; end if;
  if (select count(*) from public.campuses) <> 4 then raise exception 'SEED_CAMPUSES_MISMATCH'; end if;
  if (select count(*) from public.students) <> 50 then raise exception 'SEED_STUDENTS_MISMATCH'; end if;
  if (select count(*) from public.courses) < 8 then raise exception 'SEED_COURSES_INSUFFICIENT'; end if;
  if (select count(*) from public.sections) < 4 then raise exception 'SEED_SECTIONS_INSUFFICIENT'; end if;
  if (select count(*) from public.waitlist_entries where waitlist_status='waiting') < 1 then raise exception 'SEED_WAITLIST_EDGE_MISSING'; end if;
  if (select count(*) from public.student_marks) < 40 then raise exception 'SEED_MARKS_INSUFFICIENT'; end if;

  if app.section_remaining_capacity(app.demo_uuid('section:dmu:ba101:b')) <> 0 then
    raise exception 'CAPACITY_CALCULATION_FAILED';
  end if;

  if not app.has_schedule_conflict(
    app.demo_uuid('student:dmu:1'), app.demo_uuid('section:dmu:stat101:a')
  ) then raise exception 'TIMETABLE_CONFLICT_TEST_FAILED'; end if;

  v_grade := app.resolve_grade(app.demo_uuid('grading:dmu:1'), 86);
  if v_grade->>'letter_grade' <> 'A' or (v_grade->>'grade_point')::numeric <> 4 then
    raise exception 'GRADE_RESOLUTION_FAILED: %', v_grade;
  end if;

  begin
    insert into public.students (
      institution_id, campus_id, student_number, full_name, status
    ) values (
      app.demo_uuid('institution:university'),
      app.demo_uuid('campus:dcs:north'),
      'INVALID-CROSS-TENANT', 'Invalid Cross Tenant', 'active'
    );
    raise exception 'CROSS_TENANT_FOREIGN_KEY_DID_NOT_FAIL';
  exception when foreign_key_violation then
    null;
  end;
end
$verify$;

-- 2. Transactional RPC and idempotency test; no durable test student remains.
begin;
select set_config('request.jwt.claim.role','service_role',true);
do $rpc_test$
declare
  v_request jsonb;
  v_first jsonb;
  v_second jsonb;
begin
  v_request := jsonb_build_object(
    'operation','student.profile.submit',
    'correlation_id','11111111-1111-4111-8111-111111111111',
    'idempotency_key','phase2-hosted-idempotency-test',
    'institution_id',app.demo_uuid('institution:university'),
    'campus_id',app.demo_uuid('campus:dmu:islamabad'),
    'source',jsonb_build_object('source_submission_id','phase2-hosted-test'),
    'payload',jsonb_build_object(
      'student_number','DMU-PHASE2-VERIFY',
      'full_name','Phase Two Verification Student',
      'primary_email','phase2.verify@example.test'
    )
  );
  v_first := public.rpc_submit_student_profile(v_request);
  v_second := public.rpc_submit_student_profile(v_request);
  if not coalesce((v_first->>'success')::boolean,false) then
    raise exception 'RPC_SUBMISSION_FAILED: %', v_first;
  end if;
  if v_first <> v_second then
    raise exception 'RPC_IDEMPOTENCY_FAILED: first %, second %', v_first, v_second;
  end if;
  if v_first#>>'{data,student_id}' is null then
    raise exception 'RPC_RESPONSE_SHAPE_FAILED: %', v_first;
  end if;
end
$rpc_test$;
rollback;

-- 3. One final result set. Any failed assertion above stops execution.
select jsonb_build_object(
  'success', true,
  'suite', 'phase2-hosted-verification',
  'migrations_verified', 8,
  'public_tables', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'),
  'rls_enabled_tables', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity),
  'public_rpc_wrappers', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'rpc_%'),
  'policies', (select count(*) from pg_policies where schemaname='public'),
  'institutions', (select count(*) from public.institutions),
  'campuses', (select count(*) from public.campuses),
  'students', (select count(*) from public.students),
  'courses', (select count(*) from public.courses),
  'sections', (select count(*) from public.sections),
  'student_marks', (select count(*) from public.student_marks),
  'idempotency_transaction_rolled_back', true
) as phase2_verification;
