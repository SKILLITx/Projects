-- Workflow 09 database acceptance suite.
-- Runs inside one transaction and rolls back maintenance rows and any temporary
-- operational changes. It does not expose notification recipients or incident details.

begin;

do $test$
declare
  v_actor uuid;
  v_dmu uuid;
  v_snapshot jsonb;
  v_dry jsonb;
  v_run jsonb;
  v_replay jsonb;
  v_denied jsonb;
  v_corr uuid := gen_random_uuid();
  v_before_runs bigint;
  v_after_runs bigint;
begin
  select sp.auth_user_id
  into v_actor
  from public.staff_profiles sp
  where lower(sp.email) = lower('zaidrizwan.278@gmail.com')
    and sp.status = 'active'
  limit 1;

  select i.id into v_dmu
  from public.institutions i
  where i.code = 'DMU'
  limit 1;

  if v_actor is null or v_dmu is null then
    raise exception 'WORKFLOW09_REQUIRED_PILOT_FIXTURE_MISSING';
  end if;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_snapshot := public.rpc_get_operations_snapshot(jsonb_build_object(
    'operation','operations.snapshot',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow09:snapshot',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',v_dmu,'campus_id',null),
    'payload',jsonb_build_object(
      'backup_max_age_hours',48,
      'retention_workflow_days',90,
      'retention_incident_days',180,
      'retention_delivery_days',180
    )
  ));

  if v_snapshot->>'success' <> 'true'
     or jsonb_typeof(v_snapshot#>'{data,workflow_runs}') <> 'object'
     or jsonb_typeof(v_snapshot#>'{data,notifications}') <> 'object'
     or jsonb_typeof(v_snapshot#>'{data,incidents}') <> 'object'
     or jsonb_typeof(v_snapshot#>'{data,waitlist}') <> 'object'
     or jsonb_typeof(v_snapshot#>'{data,marks}') <> 'object'
     or jsonb_typeof(v_snapshot#>'{data,backup}') <> 'object'
     or jsonb_typeof(v_snapshot#>'{data,retention}') <> 'object'
     or jsonb_typeof(v_snapshot#>'{data,by_institution}') <> 'array' then
    raise exception 'WORKFLOW09_SNAPSHOT_SHAPE_FAILED';
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  select count(*) into v_before_runs
  from ops.maintenance_runs
  where operation = 'operations.maintenance.apply';

  v_dry := public.rpc_apply_scheduled_maintenance(jsonb_build_object(
    'operation','operations.maintenance.apply',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow09:dry-run',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',null,'campus_id',null),
    'payload',jsonb_build_object(
      'dry_run',true,
      'stale_claim_minutes',15,
      'stale_draft_days',90,
      'notification_backlog_threshold',100000,
      'waitlist_threshold',100000,
      'overdue_marks_threshold',100000,
      'open_incident_threshold',100000
    )
  ));

  select count(*) into v_after_runs
  from ops.maintenance_runs
  where operation = 'operations.maintenance.apply';

  if v_dry->>'success' <> 'true'
     or v_dry#>>'{data,dry_run}' <> 'true'
     or v_before_runs <> v_after_runs then
    raise exception 'WORKFLOW09_DRY_RUN_SIDE_EFFECT_FAILED';
  end if;

  v_run := public.rpc_apply_scheduled_maintenance(jsonb_build_object(
    'operation','operations.maintenance.apply',
    'correlation_id',v_corr,
    'idempotency_key','dbtest:workflow09:actual',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',null,'campus_id',null),
    'payload',jsonb_build_object(
      'dry_run',false,
      'stale_claim_minutes',1440,
      'stale_draft_days',3650,
      'notification_backlog_threshold',100000,
      'waitlist_threshold',100000,
      'overdue_marks_threshold',100000,
      'open_incident_threshold',100000
    )
  ));

  v_replay := public.rpc_apply_scheduled_maintenance(jsonb_build_object(
    'operation','operations.maintenance.apply',
    'correlation_id',v_corr,
    'idempotency_key','dbtest:workflow09:actual-replay',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',null,'campus_id',null),
    'payload',jsonb_build_object('dry_run',false)
  ));

  if v_run->>'success' <> 'true'
     or v_replay->>'success' <> 'true'
     or v_replay#>>'{data,replayed}' <> 'true'
     or v_run#>>'{data,maintenance_run_id}' is null
     or v_run#>>'{data,maintenance_run_id}' <> v_replay#>>'{data,maintenance_run_id}' then
    raise exception 'WORKFLOW09_MAINTENANCE_IDEMPOTENCY_FAILED';
  end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  v_denied := public.rpc_apply_scheduled_maintenance(jsonb_build_object(
    'operation','operations.maintenance.apply',
    'correlation_id',gen_random_uuid(),
    'idempotency_key','dbtest:workflow09:auth-denial',
    'source',jsonb_build_object('channel','database_test'),
    'context',jsonb_build_object('institution_id',null,'campus_id',null),
    'payload',jsonb_build_object('dry_run',true)
  ));

  if v_denied->>'success' <> 'false'
     or v_denied#>>'{error,code}' <> 'AUTH_SERVICE_ROLE_REQUIRED' then
    raise exception 'WORKFLOW09_AUTHENTICATED_MAINTENANCE_DENIAL_FAILED';
  end if;
end;
$test$;

select jsonb_pretty(jsonb_build_object(
  'status','PASS',
  'suite','workflow09-operations-monitoring',
  'checks',jsonb_build_array(
    'authorized institution-scoped snapshot',
    'zero-safe monitoring response shape',
    'service-role dry run without side effects',
    'maintenance correlation replay',
    'authenticated maintenance denial'
  ),
  'rolled_back',true
)) as workflow09_database_tests;

rollback;
