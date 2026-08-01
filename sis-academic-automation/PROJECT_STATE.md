# Project State

## Project

University and School Chain Administration Automation

## Current classification

- Portfolio/demo ready: **Yes — core academic, administrative and operational pilot paths are demonstrated**
- Controlled pilot ready: **Not yet — Workflow 10 and final integrated verification remain**
- Hosted production ready: **No**

## Completed and protected workflows

The following workflows are working, verified and protected from Workflow 10 changes:

- Workflow 01 — Student Intake and Profile Management
- Workflow 02 — Course and Subject Enrollment Lifecycle
- Workflow 03 — Marks Intake and Validation
- Workflow 04 — Results Approval and Publication
- Workflow 05 — Transcript Request, Generation and Delivery
- Workflow 07 — Administrative Search and Basic Dashboard
- Workflow 08 — Notification Dispatcher
- Workflow 09 — Scheduled Operations and Monitoring

Workflow 06 remains deliberately deferred for the current controlled pilot.

## Workflow 07 freeze

Workflow 07 remains **complete, accepted and frozen**. It must not be changed unless a genuine regression is demonstrated.

## Workflow 09 freeze

Workflow 09 is **complete, accepted, published and frozen**.

Verified evidence:

- 203 local static checks passed;
- 22 hosted database verification checks passed;
- rollback-only database acceptance passed;
- manual n8n execution reached `Log Monitoring Completion`;
- live acceptance passed;
- the latest Workflow 09 run was durably recorded as `completed`;
- the latest maintenance run was durably recorded as `completed`;
- invalid institution UUID handling was sanitized;
- authenticated browser actors were denied maintenance execution;
- the 15-minute Schedule Trigger was published and confirmed active.

Live evidence retained:

- `evidence/workflow09-acceptance-2026-07-21T01-24-53-009Z.json`
- `evidence/workflow09-freeze-2026-07-21.md`

Workflow 09 must not be changed unless a genuine regression is demonstrated.

## Workflow 09 accepted limitations

- host backup execution remains outside n8n;
- no backup verification record currently means `backup.status = not_recorded`;
- automatic Google Sheets dashboard refresh remains deferred;
- retention deletion remains disabled;
- Workflow 08 remains the sole Gmail delivery owner.

## Current phase

**Phase 4 — Workflow 10: Global Error Handler preflight**

Status: **Preflight package generated; read-only local and hosted inspection required before design freeze or migration generation**

## Workflow 10 preflight boundaries

The preflight will inspect:

- installed n8n version and node catalogue;
- exact n8n 2.4.0 Error Trigger availability;
- existing workflow names and active flags without exporting secrets;
- unsupported Crypto-node references and whether they appear connected;
- incident, incident-event, workflow-run and notification-outbox structures;
- current incident RPC, helper functions, grants, enum values, RLS and indexes;
- sanitized operational counts and configuration-table candidates.

The preflight does not create:

- `workflows/10-global-error-handler.json`;
- a Workflow 10 migration;
- new credentials;
- new database records;
- Gmail messages;
- retries of failed business workflows.

## Known limitations

- local Windows, npm-hosted n8n, SQLite metadata and ngrok remain controlled-pilot infrastructure;
- the stored Workflow 05 export may contain a legacy unsupported Crypto-node reference and must be classified by the preflight rather than copied into Workflow 10;
- full concurrency, full-cycle, backup/restore and clean-install verification remain final integration work;
- production hosting, centralized APM and distributed tracing remain outside this pilot.

## Next required action

Run `scripts\Test-Workflow10LocalPreflight.ps1`, then run the copied read-only Workflow 10 SQL preflight in Supabase and return both outputs before Workflow 10 is built.

<!-- SIS_FINAL_CONTROLLED_PILOT_STATUS -->
## Final controlled-pilot status

- Workflows 01-05, 07, 08, and 09: complete and verified.
- Workflow 06 - HEC Reporting: deferred.
- Workflow 10 - Global Error Handler: deferred.
- Full end-to-end demonstration: complete.
- Final integration acceptance: complete.
- Private backup verification: complete.
- Isolated restore verification: complete.
- Unified startup verification: complete.
- Final documentation: installed under docs/final/.
- Classification: controlled institutional pilot, not hosted production.

