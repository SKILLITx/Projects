# Public RPC Contract

## 1. Contract rule

Every public RPC accepts a single named argument:

```text
p_request jsonb
```

Every RPC returns exactly one `jsonb` object. It never relies on an empty rowset to represent a result.

## 2. Standard request envelope

```json
{
  "operation": "student.profile.submit",
  "correlation_id": "uuid",
  "idempotency_key": "source-specific-value",
  "institution_id": "uuid",
  "campus_id": "uuid-or-null",
  "requester": {
    "type": "student|teacher|staff|system",
    "auth_user_id": "uuid-or-null",
    "email": "sanitized-email-or-null"
  },
  "submitted_at": "ISO-8601 timestamp",
  "source": {
    "channel": "google_form|staff_portal|schedule|manual_test",
    "source_submission_id": "stable-source-id"
  },
  "payload": {}
}
```

Caller-supplied requester fields are audit hints only. Authenticated RPCs derive authority from `auth.uid()` and database assignments. Public-form RPCs are called only from trusted n8n server-side workflows.

## 3. Standard success response

```json
{
  "success": true,
  "operation": "student.profile.submit",
  "correlation_id": "uuid",
  "idempotency_key": "value",
  "data": {},
  "warnings": []
}
```

## 4. Standard failure response

```json
{
  "success": false,
  "operation": "student.profile.submit",
  "correlation_id": "uuid",
  "error": {
    "code": "STABLE_ERROR_CODE",
    "message": "Sanitized user-facing message",
    "retryable": false
  }
}
```

## 5. Proposed public RPC catalog

| RPC | Auth path | Purpose |
|---|---|---|
| `rpc_submit_student_profile` | Trusted server | Create/update student and document status idempotently |
| `rpc_submit_enrollment_request` | Trusted server | Evaluate and transact enrollment/waitlist/manual-review outcome |
| `rpc_decide_enrollment` | User JWT | Registrar/campus decision on manual-review request |
| `rpc_promote_waitlist` | User JWT or scheduled trusted server | Capacity-safe waitlist promotion |
| `rpc_submit_marks_batch` | Trusted restricted-form server or user JWT | Create draft batch/version and validation summary |
| `rpc_finalize_marks_batch` | Trusted restricted-form server or user JWT | Finalize one batch version idempotently |
| `rpc_decide_marks_batch` | User JWT | Approve or reject finalized marks |
| `rpc_request_mark_correction` | User JWT or controlled student route | Create correction request |
| `rpc_decide_mark_correction` | User JWT | Approve/reject correction and preserve history |
| `rpc_publish_results` | User JWT | Calculate and publish deterministic results |
| `rpc_create_transcript_request` | Trusted server or user JWT | Authorize and reserve transcript request |
| `rpc_get_transcript_model` | Trusted server or user JWT | Return one complete transcript data model |
| `rpc_record_transcript_document` | Trusted server | Record Drive/PDF generation result |
| `rpc_create_hec_report_run` | User JWT | Create authorized report job |
| `rpc_get_hec_enrollment_data` | User JWT or trusted report worker | Return filtered demonstration report model |
| `rpc_record_generated_report` | Trusted server | Record report files and completion state |
| `rpc_search_students` | User JWT | Institution/campus-scoped sanitized search |
| `rpc_get_dashboard_snapshot` | User JWT or trusted scheduled server | Return dashboard data as one object |
| `rpc_claim_notifications` | Trusted server | Atomically claim pending outbox rows |
| `rpc_record_notification_attempt` | Trusted server | Record delivery/retry/dead-letter outcome |
| `rpc_get_operations_snapshot` | User JWT or trusted scheduled server | Return health and backlog metrics |
| `rpc_apply_scheduled_maintenance` | Trusted server | Execute approved database-side maintenance transitions |
| `rpc_record_incident` | Trusted server | Create/deduplicate root incident and append event |
| `rpc_log_workflow_run` | Trusted server | Start/update workflow-run evidence |

## 6. Internal-only functions

Public wrappers may call internal functions such as:

- `app.resolve_policy_version`
- `app.authorize_operation`
- `app.evaluate_prerequisites`
- `app.detect_schedule_conflicts`
- `app.allocate_section`
- `app.place_waitlist`
- `app.validate_marks_batch`
- `app.calculate_course_results`
- `app.recalculate_student_academic_record`
- `app.build_transcript_model`
- `app.build_hec_report_model`
- `ops.claim_notification_batch`
- `ops.upsert_incident`

These functions are not called directly by n8n through PostgREST.

## 7. Stable error-code groups

- `AUTH_*` — token, role or scope failure
- `VALIDATION_*` — malformed or invalid business input
- `CONFIG_*` — missing or inconsistent institution configuration
- `STUDENT_*` — student state or identity problem
- `ENROLLMENT_*` — period, prerequisite, capacity, conflict or duplicate
- `MARKS_*` — assignment, range, version or finalization problem
- `RESULT_*` — approval/publication/calculation state problem
- `TRANSCRIPT_*` — authorization, record or generation state problem
- `REPORT_*` — filter, template or run-state problem
- `NOTIFICATION_*` — claim or delivery-state problem
- `INCIDENT_*` — incident-recording problem
- `SYSTEM_*` — temporary infrastructure or unexpected internal failure

Raw SQL, stack traces, private schema names, provider bodies and credentials are never returned in public errors.

## 8. Idempotency behaviour

On a repeated valid idempotency key:

- compare the stored request hash;
- return the stored result if the hash matches;
- return `VALIDATION_IDEMPOTENCY_KEY_REUSED` if the same key is reused for a materially different request;
- do not repeat database or external side effects.

External calls use durable job state so a workflow retry can resume without generating duplicate documents or email deliveries.
