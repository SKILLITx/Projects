# Workflow 09 — Scheduled Operations and Monitoring

## Status

Generated for the controlled pilot. The workflow must not be frozen until the hosted migration, database suite, n8n import, manual live execution and acceptance script all pass.

## Workflow identity

- **n8n name:** `SIS 09 — Scheduled Operations and Monitoring — Complete`
- **Portable file:** `workflows/09-operations-monitoring.json`
- **Schedule:** every 15 minutes
- **Credential:** `SIS Supabase Service Role`

## Owned outcomes

Workflow 09 owns one scheduled operational cycle:

1. Record the workflow run as started.
2. Apply bounded maintenance through `public.rpc_apply_scheduled_maintenance`.
3. Retrieve one zero-safe monitoring snapshot through `public.rpc_get_operations_snapshot`.
4. Record completed metrics in `ops.workflow_runs`.
5. Record or deduplicate an incident when maintenance or snapshot retrieval fails.

The database, not n8n Code nodes, owns operational aggregation, bounded maintenance, alert thresholds, alert deduplication and role checks.

## Monitoring snapshot

The snapshot contains:

- workflow executions in the last 24 hours;
- stale `started` workflow runs;
- pending, claimed and dead-letter notifications;
- open, acknowledged and critical incidents;
- waiting students and oldest waitlist age;
- marks drafts, stale drafts and overdue sections;
- pending dashboard-refresh records;
- latest host backup-verification status;
- retention-review counts;
- per-institution operational summaries;
- the latest Workflow 09 execution and maintenance records.

Every category is represented with a predictable object and numeric zero values when no rows exist.

## Bounded maintenance

The maintenance RPC may:

- release notification claims older than the bounded stale-claim threshold;
- dead-letter notifications that exhausted their attempts;
- supersede marks drafts older than the bounded stale-draft threshold;
- create one deduplicated daily email alert per institution when actionable thresholds are crossed;
- write one durable `ops.maintenance_runs` record.

It does not:

- delete academic or operational records;
- execute PowerShell or shell commands;
- run host backups;
- directly refresh Google Sheets;
- perform retention deletion;
- modify enrollment, published results or transcripts.

A `dry_run` option supports rollback-safe database verification.

## Alert recipient selection

For each institution, the database chooses the first active registrar, administrator or campus administrator. When none exists, it falls back to an active super administrator. If no eligible recipient exists, the condition is counted as suppressed rather than inserting an invalid outbox row.

Alert rows use the existing notification outbox and a daily idempotency key, preventing one monitoring cycle from generating duplicate alerts.

## Security

- Scheduled maintenance is executable only by `service_role`.
- The read-only snapshot is executable by `service_role` and authorized staff.
- A global authenticated snapshot requires an active super administrator.
- An institution snapshot requires super-administrator or institution-administrator scope.
- n8n calls only stable `public` RPC wrappers.
- No service key, access token, credential ID or live ngrok URL is in the workflow export.
- All workflow HTTP nodes bind the existing `SIS Supabase Service Role` credential.
- Failure incidents contain sanitized stage/status information only.

## Backup boundary

Workflow 09 does not execute backups. The snapshot observes the newest `ops.maintenance_runs` record whose operation is `backup.verify`. Backup creation and restore verification remain host-level PowerShell responsibilities.

When no verification record exists, the snapshot returns `backup.status = "not_recorded"` and adds a warning. This is a monitoring result, not a false claim that backups failed.

## Deferred scope

The following remain explicitly deferred:

- automatic Google Sheets dashboard refresh;
- automatic retention deletion;
- hosted infrastructure health checks outside PostgreSQL;
- n8n/SQLite backup execution;
- centralized UI for incident acknowledgement;
- advanced charts and cross-institution BI.

## Import and activation

1. Apply and verify migration `20260721000300_phase4_workflow09_operations_monitoring.sql`.
2. Import `workflows/09-operations-monitoring.json`.
3. Confirm every HTTP node is bound to `SIS Supabase Service Role`.
4. Activate the workflow.
5. Use **Execute workflow** once in the n8n editor to create immediate live evidence.
6. Run `scripts/Run-Workflow09Acceptance.ps1`.
7. Leave the 15-minute schedule active only after acceptance passes.
