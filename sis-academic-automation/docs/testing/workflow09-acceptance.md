# Workflow 09 Acceptance Guide

## Verification order

1. Install the Workflow 09 package into the current repository.
2. Run the static suite.
3. Run the read-only contract snapshot in Supabase.
4. Apply the immutable Workflow 09 migration.
5. Run compact hosted verification.
6. Run the rollback-only database acceptance suite.
7. Import and configure the n8n workflow.
8. Manually execute it once.
9. Run the live acceptance script.
10. Activate the schedule and freeze the workflow only after PASS.

## Static suite

Run:

```powershell
& ".\scripts\Test-Workflow09Static.ps1"
```

It verifies the exact workflow name, supported n8n 2.4.0 node families and versions, the 15-minute trigger, public-RPC-only URLs, service-role credential binding, connection integrity, Code-node syntax, secret exclusion, migration boundaries, verification coverage and package exclusions.

## Database contract snapshot

`database/queries/workflow09-contract-snapshot.sql` is read-only. It inspects:

- `rpc_get_operations_snapshot`;
- `rpc_apply_scheduled_maintenance`;
- `rpc_record_incident`;
- `rpc_log_workflow_run`;
- operational and academic relation columns;
- relevant indexes and grants.

Do not apply the migration until the snapshot is reviewed.

## Hosted verification

`database/queries/workflow09-verification.sql` returns one JSON object. Expected:

```json
{
  "status": "PASS",
  "failed": 0
}
```

The checks cover signatures, grants, service-only maintenance, authorization logic, zero-safe sections, dry run, correlation replay, bounded updates, no deletion, alert idempotency and monitoring indexes.

## Database acceptance

Run `database/tests/workflow09-operations-monitoring.sql` in a new Supabase SQL Editor query.

The suite:

- validates an authorized institution-scoped snapshot;
- confirms stable zero-safe objects and arrays;
- confirms `dry_run` creates no maintenance record;
- performs an actual maintenance call inside the transaction;
- confirms the same correlation ID replays the same maintenance run;
- confirms an authenticated browser actor cannot run maintenance;
- ends with `ROLLBACK`.

Expected result:

```json
{
  "status": "PASS",
  "suite": "workflow09-operations-monitoring",
  "rolled_back": true
}
```

## Live n8n verification

After importing the workflow:

1. Bind `SIS Supabase Service Role` to every HTTP Request node.
2. Keep it inactive while inspecting node configuration.
3. Click **Execute workflow** once.
4. Confirm the final execution path reaches `Log Monitoring Completion`.
5. Confirm no failure incident branch runs.
6. Activate the workflow.

The workflow has a Schedule Trigger, so manual editor execution is the controlled way to generate immediate evidence.

## Live acceptance script

Run:

```powershell
& ".\scripts\Run-Workflow09Acceptance.ps1"
```

The script securely prompts for the staff password and uses the browser-safe Supabase anon configuration. It never requests or reads the service-role key.

It validates:

- authorized DMU snapshot;
- zero-safe metric types;
- super-administrator global snapshot;
- latest completed n8n Workflow 09 run;
- latest completed maintenance run;
- sanitized invalid UUID handling;
- authenticated denial for the maintenance RPC.

Evidence is written to `evidence/workflow09-acceptance-<timestamp>.json`.

## Expected pilot warning

Until a host backup verification writes an `ops.maintenance_runs` record with operation `backup.verify`, the snapshot will report:

```text
backup.status = not_recorded
```

This does not fail the acceptance suite. It documents an unresolved host-level operational dependency.

## Failure method

When a test fails:

1. identify the first incorrect state;
2. determine whether it is workflow, credential, network, RPC, authorization or data shape;
3. run the smallest failing test;
4. repair the correct layer;
5. add regression coverage;
6. rerun static, hosted verification, database acceptance and live acceptance.

Do not patch downstream output while leaving the RPC or authorization cause unresolved.
