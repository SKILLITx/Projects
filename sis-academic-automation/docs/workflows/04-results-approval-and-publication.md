# Workflow 04 — Results Approval and Publication

## Implemented operations

- `POST /webhook/staff/rpc_decide_marks_batch`
- `POST /webhook/staff/rpc_decide_mark_correction`
- `POST /webhook/staff/rpc_publish_results`
- Google Forms Automation Queue processing for `marks.correction.request`

## Authorization

Staff webhook requests are authenticated in two layers:

1. n8n validates the incoming Supabase access token through the Supabase Auth
   user endpoint.
2. n8n overwrites the request identity with the verified user ID and email.
3. the service-role database RPC resolves the active staff profile and enforces
   super-administrator, registrar or campus-administrator scope.

Teachers may submit correction requests only for a section to which they are
actively assigned. Teachers cannot approve marks, decide corrections or publish
institutional results unless they also hold an administrative role.

## Result calculations

Grading rules remain in Supabase:

- assessment-component weights come from `assessment_components`;
- grade bands and grade points come from `grade_scales`;
- rounding and repeat policy come from
  `grading_policies.calculation_method`;
- academic standing and at-risk status come from
  `academic_standing_rules`.

Missing required assessments produce an incomplete result. Withdrawn and audit
enrollments are excluded from GPA and CGPA. Repeated-course cumulative handling
supports `latest_attempt`, `highest_grade` and `all_attempts`, defaulting to
`latest_attempt`.

## Idempotency

Marks decisions, correction requests, correction decisions and publication use
`ops.idempotency_records`. A repeated request using the same key and payload
returns the stored result without repeating side effects.

## Notifications and audit

Business functions write notification jobs to `ops.notification_outbox` and
durable actor/action evidence to `audit.audit_logs`. Workflow 08 remains the
single email-delivery owner.
