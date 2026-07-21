# Changelog

All notable project changes will be recorded here.

## 0.0.1 — Phase 0 architecture package

### Added

- Initial project state.
- Confirmed requirements and assumptions.
- Final logical and deployment architecture.
- Workflow boundary catalog.
- Data-flow diagrams.
- Role and authorization matrix.
- Database entity catalog.
- Public RPC contract.
- Google Workspace structure.
- Repository plan.
- Risk register.
- Implementation sequence.
- Phase 0 review checklist.
- Machine-readable CSV catalogs.
- Phase 0 manifest and checksums.

### Not added by design

- n8n workflow exports.
- SQL migrations.
- runtime scripts.
- Google templates.
- portal code.
- credentials or secrets.

## 0.1.1 — Phase 1 static-validator repair

### Fixed

- Excluded `node_modules`, `.runtime`, `.n8n`, `.git` and generated/backup/export paths from committed-source secret scanning.
- Prevented third-party dependency examples and local n8n credential metadata from producing false-positive secret findings.

### Verified

- The validator passes when secret-like examples exist only in excluded dependency/runtime paths.
- The validator fails when the same secret-like value is placed in a repository-authored source file.

### Documented

- Recorded the user’s successful Windows initialization, environment validation and n8n/ngrok startup.
- Recorded the inherited npm vulnerability report as a separate security-review item; no forced dependency mutation was performed.

## 0.1.2 — Phase 1 completed

### Verified

- Repaired static repository validation passed on Windows.
- Local n8n `/healthz` returned HTTP 200.
- Public ngrok `/healthz` returned HTTP 200.
- Controlled n8n and ngrok shutdown passed.
- Clean restart and final health validation passed.

### Changed

- Marked Phase 1 complete.
- Advanced project state to Phase 2, pending creation of a new Supabase project.
- Added `evidence/phase-1-runtime-verification.md`.

### Remaining limitation

- Inherited npm dependency vulnerabilities remain documented and were not modified with automatic audit-fix commands.

## 0.2.1 — Phase 2 foundation verified and identity migration generated

### Verified

- Foundation migration applied to the hosted Supabase project.
- Local and remote migration history matched.
- Internal schemas `app`, `audit`, `ops` and `reporting` exist.
- RLS is enabled on all six foundation tables.
- `anon` and `authenticated` had no direct foundation-table privileges before identity policies.

### Added

- Staff profile model.
- Institution-scoped role assignments.
- Campus assignments.
- Optional permission overrides.
- Authorization helper functions.
- Scoped authenticated read policies.
- Private authorization event catalog.
- Tranche 2 verification SQL.

### Security

- Direct authenticated writes remain disabled.
- Authorization is based on `auth.uid()` and database assignments.
- No first administrator or credential was created automatically.

## 0.2.2 — Phase 2 accelerated completion batch

### Verified

- Identity and authorization migration applied.
- Four authorization tables have RLS enabled.
- Ten scoped SELECT policies exist across foundation and authorization tables.
- `authenticated` has SELECT-only access to authorization tables; `anon` has none.

### Added

- Six ordered migrations covering curriculum through demonstration data.
- Complete student, enrollment, marks, result, transcript, HEC, notification, workflow-run, incident and audit models.
- Twenty-four stable public JSON RPC wrappers.
- Deterministic fictional seed for two institutions and 50 students.
- Hosted database verification suite.
- Migration checksum verifier.
- ERD, data dictionary, RPC dictionary, RLS guide, test guide and completeness matrix.

### Fixed during construction validation

- Added a composite tenant key needed by enrollment foreign keys.
- Added explicit enum casts in seed union branches.
- Replaced UUID aggregation in academic-record recalculation with deterministic row selection.

### Validation

- PostgreSQL parser accepted all six new migrations.
- PostgreSQL-compatible execution accepted the complete 001–008 chain.
- Seed, RLS, RPC shape, capacity, conflict, grading and idempotency checks passed.

## 0.2.3 — pgcrypto extension-schema repair

### Failure identified

- Remote migration 007 could not resolve `digest(bytea, text)` because Supabase keeps pgcrypto under the `extensions` schema and the function used a restricted search path.
- Migrations 003–006 had applied successfully.
- Migration 007 rolled back and migration 008 was not attempted.

### Fixed

- Qualified every pgcrypto digest call in pending migrations 007 and 008 as `extensions.digest(...)`.
- Corrected the PowerShell 5.1 migration-count display.
- Added a one-command repair, push, migration-history and verification-copy script.

### Regression validation

- Re-executed the complete 001–008 chain with digest available only under `extensions`.
- Verified 50 seeded students, 24 RPC wrappers and stable idempotent RPC replay.
- No already-applied migration was modified.

## 0.3.0 — Phase 2 completed and Phase 3 package generated

### Phase 2 verified

- Hosted verification passed for eight migrations, 56 RLS tables, 59 policies and 24 RPC wrappers.
- Demonstration data verified: two institutions, four campuses, 50 students, ten courses, nine sections and 40 student marks.
- Idempotency rollback verification passed.

### Phase 3 added

- Six Google Form definitions and field catalog.
- Linked response-sheet and normalized Automation Queue contracts.
- Twelve-folder Google Drive plan.
- Idempotent Apps Script provisioner and asset verifier.
- Transcript Google Docs template.
- HEC reporting Google Sheets template.
- Operational dashboard Google Sheets template.
- Asset registry spreadsheet.
- Supabase Auth staff portal.
- Local portal configuration and server scripts.
- First-staff bootstrap SQL generator.
- Authorization verification SQL generator and 15-case test matrix.

### Security

- Browser code accepts only the Supabase anon key.
- Service-role credentials remain server-side.
- Staff scope is derived from Supabase Auth and database role assignments.
- Google asset identifiers are recorded in the asset registry instead of hardcoded in portable workflows.

## 0.4.0 — Phase 4 Wave 1 generated

### Added

- Student intake and profile-management n8n workflow.
- Enrollment lifecycle n8n workflow.
- Notification-outbox dispatcher n8n workflow.
- Form-code resolution RPCs for student and enrollment Google Forms.
- Pre-send notification attempt reservation and idempotent attempt finalization.
- Google asset-ID helper, environment configurator and workflow importer.
- Wave 1 database verification, workflow static suite and test fixtures.

### Reliability

- Business idempotency remains database-enforced.
- HTTP transport retries are bounded to three attempts.
- Gmail has no node-level retry; the database outbox is the sole retry owner.
- A replayed notification attempt does not call the provider again.
- An uncertain stale provider outcome is dead-lettered rather than duplicated.

### Security

- No credentials or credential IDs appear in workflow exports.
- No direct calls to private database schemas exist.
- Identity references are hashed inside PostgreSQL before durable core storage.
- Workflow execution payload persistence is disabled for Wave 1.

## 0.4.1 — Wave 1 pre-application hardening

### Fixed

- Preserved blank preferred-section positions so course/section arrays remain aligned.
- Rejected duplicate course and document codes explicitly.
- Added wrapper-level replay of completed idempotent results even when a retry has a new correlation ID.
- Enforced email, date of birth and mobile fields for student intake.
- Enforced guardian name and phone for Cambridge/subject-based institutions.
- Prevented notification workflow logs from reporting completion when delivery finalization fails.

### Expanded validation

- Added valid enrollment allocation.
- Added missing-document rejection.
- Added duplicate-course rejection.
- Added forbidden-fallback rollback.
- Added Cambridge-school guardian validation.
- Added request-normalizer regression tests.
- Hosted verification now contains nine rolled-back checks.



## 0.4.8 — Workflow 07 catalog privilege-check repair

### Fixed

- Replaced text-based `has_function_privilege` signatures in the Workflow 07 contract snapshot and hosted verification with the `pg_proc` OID overload.
- Prevented PostgreSQL from reparsing `p_request jsonb` as a type name, which caused SQLSTATE `42601` / `invalid type name "p_request jsonb"`.
- Added static regression checks so named identity arguments cannot be passed through a formatted `regprocedure` signature again.

### Verification status

- Local Workflow 07 static suite passes with 226 checks.
- Hosted contract snapshot remains pending rerun after this repair.

## 0.4.7 — Workflow 07 complete package generated

### Inspected

- Existing n8n 2.4.0 package pin and proven node/typeVersion patterns from working workflows.
- Existing partial Workflow 07 export, portal integration, database functions, migrations, role enum and authorization helpers.
- Existing immutable `20260721000100` migration, which did not satisfy the revised search/dashboard contract.

### Added

- Exact `SIS 07 — Administrative Search and Basic Dashboard — Complete` workflow with separate authenticated student-search and dashboard branches.
- Explicit Respond to Webhook nodes on every success and failure path.
- Read-only Workflow 07 contract snapshot.
- Immutable `20260721000200` repair migration with stable search/dashboard RPCs, reviewed search indexes and a hash-only fictional identity fixture.
- Compact verification SQL and a transactional role/scope/database contract test.
- Installer, clipboard helpers, static validator and bundled positive/negative acceptance runner.
- Canonical Workflow 07 and acceptance documentation.

### Changed

- Updated the existing staff portal in place with visible search types, Clear action, human-readable term selection, twelve dashboard cards, grade distribution, course capacity and sanitized support output.
- Preserved existing Supabase Auth, role/institution/campus selectors and working administrative action tabs.
- Replaced the obsolete Workflow 07 documentation filename with `docs/workflows/07-admin-dashboard.md`.

### Security

- Business RPC calls use the verified staff bearer token and public RPC wrappers only.
- Service-role access is restricted to durable workflow-run logging.
- Teacher-only actors are denied while multi-role authorized administrators remain accepted.
- Full identity/CNIC values, tokens, credential IDs and private-schema details are excluded from public responses and package files.
- `portal/config.local.js` is never overwritten or packaged.

### Locally verified

- Workflow/portal/test JavaScript parsing.
- Exact route, connection, response-node, supported-node and typeVersion checks.
- No Crypto, Execute Command, custom/community nodes, live ngrok URL or private-schema REST access.
- PostgreSQL-compatible canonical UUID validation and 25-row search bound.

### Pending external verification

- Hosted contract snapshot, migration application and SQL verification.
- n8n import, credential binding, activation and live positive/negative acceptance.
- Portal screenshot and final Workflow 07 freeze.


## 0.4.9 — Workflow 07 installed-repository static-test repair

### Fixed

- Corrected the `config.local.js` package-exclusion check so it validates `PACKAGE_MANIFEST.sha256` instead of failing merely because the installed repository correctly preserves its local browser configuration.
- Added installer-side rejection when `.env` or `portal/config.local.js` is present in the source package.
- Added the package manifest to installed Workflow 07 support files so the exclusion check remains verifiable after installation.

### Verification status

- Package-source static suite passes.
- Simulated installation into a repository containing `portal/config.local.js` also passes the complete static suite.
- Hosted contract snapshot remains the next external step.

## 0.5.0 — Workflow 07 frozen and Workflow 09 package generated

### Workflow 07 verified and frozen

- Recorded successful 226-check static validation.
- Recorded 20/20 hosted database verification.
- Recorded rollback-only database acceptance PASS.
- Recorded positive and bundled negative live acceptance PASS.
- Recorded staff portal search and dashboard visual acceptance.
- Frozen Workflow 07 against non-regression changes.

### Workflow 09 inspected

- Reviewed the current n8n 2.4.0 package pin.
- Reused proven Schedule Trigger, Code, IF and HTTP Request node versions.
- Reviewed existing operations, notification, incident, workflow-run, waitlist, marks, section and term models.
- Reviewed the original `rpc_get_operations_snapshot` and `rpc_apply_scheduled_maintenance` functions.
- Preserved Workflows 01–05, 07 and 08 without modification.

### Workflow 09 added

- Added `SIS 09 — Scheduled Operations and Monitoring — Complete`.
- Added a 15-minute schedule-only workflow with no public webhook.
- Added durable workflow-start, completion and failure logging.
- Added sanitized incident recording for maintenance and snapshot failures.
- Added immutable migration `20260721000300_phase4_workflow09_operations_monitoring.sql`.
- Added zero-safe global and institution-scoped operations snapshots.
- Added bounded notification-claim release and stale-draft maintenance.
- Added correlation-based maintenance replay protection.
- Added deduplicated daily operational alert outbox records.
- Added backup-verification observation and retention-review metrics.
- Added contract, verification, database acceptance, static and live acceptance suites.
- Added installer, PowerShell clipboard helpers and canonical documentation.

### Security and safety

- Maintenance is service-role only.
- Authorized staff snapshot access is database-scoped.
- Global authenticated snapshot access requires a super administrator.
- No direct private-schema REST calls exist.
- No Crypto, Execute Command, custom or community nodes are used.
- No host command is executed from n8n.
- No record deletion is performed.
- No secret, token, credential ID, live ngrok URL or local portal configuration is packaged.

### Deferred

- Host backup execution and restore verification.
- Automatic Google Sheets dashboard refresh.
- Automatic retention deletion.
- Workflow 10 centralized error handling.
- Final Phase 5 integrated verification.


## 0.4.11 â€” Workflow 09 verified, activated and frozen; Workflow 10 preflight added

### Workflow 09 verified

- Installed Workflow 09 without overwriting `portal/config.local.js`.
- Passed 203 static checks.
- Applied immutable migration `20260721000300_phase4_workflow09_operations_monitoring.sql`.
- Passed 22 hosted verification checks.
- Passed rollback-only database acceptance.
- Completed one controlled manual n8n execution through `Log Monitoring Completion`.
- Passed live acceptance with durable completed workflow and maintenance records.
- Confirmed the 15-minute Schedule Trigger was published and active.

### Workflow 09 frozen

- Recorded live evidence `evidence/workflow09-acceptance-2026-07-21T01-24-53-009Z.json`.
- Added `evidence/workflow09-freeze-2026-07-21.md`.
- Preserved host backup execution, Google Sheets refresh and retention deletion as documented deferred items.
- Preserved Workflow 08 as the only Gmail delivery owner.

### Workflow 10 preflight added

- Added read-only schema, RPC and operational inspection SQL.
- Added a PowerShell 5.1 local runtime/node-catalogue inspection script.
- Added Workflow 10 preflight design, gap and test-matrix documentation.
- Did not create a Workflow 10 workflow or migration.
- Did not modify Workflows 01â€“09.


<!-- SIS_FINAL_DOCUMENTATION_CHANGELOG -->
## 2026-07-21 - Controlled pilot finalization

- Recorded Workflows 01-05 and 07-09 as completed.
- Recorded Workflows 06 and 10 as deferred.
- Added startup, recovery, limitations, handover, testing, and production migration documentation.
- Generated a sanitized evidence index.

