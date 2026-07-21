# Workflow Boundaries

## Boundary rule

A workflow owns one business domain outcome. It may call multiple database RPCs and external services, but it must not be split merely because the process has several technical steps.

## Workflow 1 — Student Intake and Profile Management

**Inputs**

- new-student Google Form row;
- profile-update request;
- authenticated staff correction request.

**Owns**

- request normalization;
- required-field validation;
- institution, campus and program validation;
- duplicate student ID, CNIC and email detection;
- safe student create/update;
- document-presence recording;
- missing-document determination;
- audit entry;
- acknowledgment outbox event.

**Does not own**

- course enrollment;
- section allocation;
- sending Gmail directly;
- transcript generation.

**Primary RPC**

- `rpc_submit_student_profile`

**Completion outcome**

One student-intake result object with created, updated, duplicate, rejected or manual-review status.

---

## Workflow 2 — Course and Subject Enrollment Lifecycle

**Inputs**

- public enrollment Form row;
- authenticated administrative decision;
- scheduled waitlist promotion request.

**Owns**

- active-student check;
- enrollment-period check;
- offering validation;
- program/campus restrictions;
- prerequisites;
- document restrictions;
- duplicate prevention;
- load limit;
- timetable conflicts;
- preferred-section evaluation;
- fallback section;
- capacity-safe allocation;
- waitlist placement;
- manual-review or rejection;
- decision history;
- enrollment notifications through outbox.

**Does not own**

- student profile creation beyond calling Workflow 1 or requiring an existing record;
- direct email;
- grade calculations.

**Primary RPCs**

- `rpc_submit_enrollment_request`
- `rpc_decide_enrollment`
- `rpc_promote_waitlist`

**Completion outcome**

Allocated, waitlisted, rejected, manual-review or idempotent-existing result.

---

## Workflow 3 — Marks Intake and Validation

**Inputs**

- restricted teacher Form;
- uploaded CSV/XLSX file;
- authenticated teacher portal submission.

**Owns**

- teacher identity and assignment check;
- file/spreadsheet extraction;
- assessment-component validation;
- student membership validation;
- maximum and range checks;
- duplicate/unknown/missing student summary;
- draft batch creation;
- version preservation;
- finalization;
- audit entry;
- confirmation outbox event.

**Does not own**

- registrar approval;
- final grade/GPA publication;
- correction approval.

**Primary RPCs**

- `rpc_submit_marks_batch`
- `rpc_finalize_marks_batch`

**Completion outcome**

A batch ID, version, status and complete validation summary.

---

## Workflow 4 — Results Approval and Publication

**Inputs**

- authenticated registrar/examination decision;
- authenticated correction request or decision;
- publication command.

**Owns**

- approve/reject finalized batch;
- correction workflow;
- weighted totals;
- letter grades and grade points;
- failed/repeated/incomplete/withdrawn handling;
- semester GPA;
- cumulative CGPA;
- academic standing;
- at-risk flags;
- publication;
- idempotent recalculation;
- outbox notifications.

**Does not own**

- teacher marks parsing;
- transcript document generation;
- notification delivery.

**Primary RPCs**

- `rpc_decide_marks_batch`
- `rpc_request_mark_correction`
- `rpc_decide_mark_correction`
- `rpc_publish_results`

**Completion outcome**

Approved/rejected/correction-required/published result with recalculation summary.

---

## Workflow 5 — Transcript Request, Generation and Delivery

**Inputs**

- public student request;
- authenticated staff request;
- retryable document job.

**Owns**

- request creation and authorization;
- academic-record availability check;
- transcript data retrieval;
- Google Docs template copy/population;
- PDF export;
- Drive storage;
- document metadata;
- approved-recipient email job;
- delivery status;
- idempotent reuse of completed request.

**Does not own**

- grade calculations;
- direct academic record changes;
- HEC reporting.

**Primary RPCs**

- `rpc_create_transcript_request`
- `rpc_get_transcript_model`
- `rpc_record_transcript_document`

**Completion outcome**

Transcript request status and, when complete, reference number plus Drive metadata.

---

## Workflow 6 — HEC Enrollment Reporting

**Inputs**

- authenticated administrator report request.

**Owns**

- scope authorization;
- institution/campus/year/term/program filters;
- report data retrieval;
- demonstration template population;
- CSV/XLSX-compatible export;
- Drive storage;
- report-run state;
- requester notification outbox event.

**Does not own**

- claiming official HEC compliance;
- changing enrollment records.

**Primary RPCs**

- `rpc_create_hec_report_run`
- `rpc_get_hec_enrollment_data`
- `rpc_record_generated_report`

**Completion outcome**

Completed or failed report run with generated file metadata.

---

## Workflow 7 — Administrative Search and Dashboard

**Trigger branch A: authenticated search webhook**

Owns scoped student search and sanitized responses.

**Trigger branch B: schedule/manual dashboard refresh**

Owns snapshot retrieval and Google Sheets dashboard refresh.

**Does not own**

- mutation of academic records;
- operational alert delivery.

**Primary RPCs**

- `rpc_search_students`
- `rpc_get_dashboard_snapshot`

**Completion outcome**

A search result object or a completed dashboard refresh record.

---

## Workflow 8 — Notification Dispatcher

**Inputs**

- schedule trigger;
- manual retry trigger.

**Owns**

- atomic notification claiming;
- Gmail send;
- provider response recording;
- bounded retry;
- permanent-failure/dead-letter transition;
- duplicate-delivery prevention;
- delivery history.

**Does not own**

- deciding that a business notification is needed;
- changing academic outcomes.

**Primary RPCs**

- `rpc_claim_notifications`
- `rpc_record_notification_attempt`

**Completion outcome**

A dispatch batch summary and durable per-notification delivery state.

---

## Workflow 9 — Scheduled Operations and Monitoring

**Inputs**

- schedule triggers.

**Owns**

- health checks;
- unresolved incident summary;
- overdue marks summary;
- waitlist backlog;
- stale draft cleanup requests;
- dashboard refresh scheduling;
- backup-status verification;
- retention checks;
- outbox backlog monitoring.

**Does not own**

- host-level backup execution;
- Execute Command;
- direct academic transactions outside approved RPCs.

**Primary RPCs**

- `rpc_get_operations_snapshot`
- `rpc_apply_scheduled_maintenance`

**Completion outcome**

A monitoring run record and outbox alerts for actionable conditions.

---

## Workflow 10 — Global Error and Incident Handling

**Inputs**

- n8n Error Trigger events;
- explicit incident events from other workflows.

**Owns**

- root incident ID;
- fingerprint and deduplication;
- workflow, operation and correlation context;
- retryable/permanent classification;
- sanitized technical detail storage;
- incident event history;
- one alert request per root incident;
- acknowledged/resolved/unresolved state.

**Does not own**

- the primary business retry;
- replacing workflow-specific error responses;
- blocking incident persistence if alerting fails.

**Primary RPC**

- `rpc_record_incident`

**Completion outcome**

Existing or newly created root incident with current state.

## Cross-workflow interaction rules

- Business workflows communicate through database state, not long webhook chains.
- Notification requests are outbox rows.
- Document jobs use durable request/job state.
- Workflow 10 records failures but does not become the retry owner.
- Workflow 9 observes and schedules; it does not execute host commands.
- `Execute Workflow` is reserved for a genuinely reusable adapter with a clear contract, not for splitting every technical step.
