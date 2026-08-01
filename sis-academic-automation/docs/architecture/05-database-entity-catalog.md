# Database Entity Catalog

This is the Phase 0 logical catalog. Exact columns, constraints and indexes are finalized in Phase 2.

## 1. Schema responsibilities

| Schema | Responsibility | Exposed through PostgREST |
|---|---|---|
| `public` | RLS-protected business records and stable RPC wrappers | Yes |
| `app` | Internal transactional helpers and rule engines | No direct n8n access |
| `audit` | Immutable audit history | No direct n8n access |
| `ops` | Idempotency, workflow runs, notifications, incidents, report jobs | No direct n8n access except public RPCs |
| `reporting` | Internal reporting views/models | No direct n8n access |

## 2. Institution and configuration

- `public.institutions` — tenant root and lifecycle status.
- `public.campuses` — institution campuses and timezone/location metadata.
- `public.institution_settings` — versioned JSON or structured operational settings.
- `public.academic_years` — academic-year boundaries.
- `public.terms` — semester, term, session or Cambridge exam-period abstraction.
- `public.enrollment_periods` — request windows and policy version.
- `public.departments` — academic ownership units.
- `public.programs` — degree, grade, class, pathway or Cambridge program.
- `public.grading_policies` — policy header and effective dates.
- `public.grade_scales` — score boundaries, letter grades and grade points.
- `public.academic_standing_rules` — warning/probation/good-standing rules.
- `public.enrollment_policies` — load, fallback and waitlist behaviour.
- `public.transcript_settings` — template, disclaimer, numbering and verification options.
- `public.notification_settings` — sender, channel and recipient rules.
- `public.hec_report_settings` — demonstration template and filter configuration.

## 3. Identity and authorization

- `public.staff_profiles` — staff identity, institutional email and optional Auth user link.
- `public.role_assignments` — role, institution, validity window and status.
- `public.campus_assignments` — campus scope for role assignments.
- `public.permission_grants` — optional operation-level exceptions.
- `public.student_auth_links` — optional Auth-to-student association.
- `audit.authorization_events` — authorization decisions requiring durable evidence.

## 4. Student records and documents

- `public.students` — canonical student identity and institutional student number.
- `public.student_contacts` — email, phone and guardian/parent contact records.
- `public.student_program_registrations` — active program, cohort, term and status.
- `public.document_requirements` — required document types by institution/program.
- `public.student_documents` — submitted document metadata and verification state.
- `public.student_profile_requests` — intake/update request and idempotency state.

## 5. Curriculum, offerings and scheduling

- `public.courses` — course or subject catalog.
- `public.course_prerequisites` — prerequisite rule edges and minimum outcomes.
- `public.course_equivalencies` — accepted equivalent courses/subjects.
- `public.course_offerings` — term-specific offering.
- `public.sections` — capacity-controlled class section.
- `public.section_schedules` — day/time/room schedule blocks.
- `public.rooms` — optional room and capacity data.
- `public.teacher_assignments` — teacher-to-offering/section assignment.
- `public.assessment_components` — policy component definitions and weights.
- `public.assessments` — offering-specific assessments and maximum marks.

## 6. Enrollment

- `public.enrollment_requests` — normalized request envelope and current status.
- `public.enrollment_request_items` — requested courses/subjects and preference order.
- `public.enrollments` — successful student-to-offering/section registration.
- `public.enrollment_decisions` — append-only decision history and evidence.
- `public.waitlist_entries` — deterministic waitlist order and status.
- `public.timetable_conflict_evidence` — recorded conflicting schedule blocks.
- `public.prerequisite_evidence` — prerequisite evaluation details.

## 7. Marks and results

- `public.marks_batches` — teacher submission header, version and lifecycle status.
- `public.marks_batch_files` — uploaded file metadata.
- `public.student_marks` — student assessment marks by batch/version.
- `public.marks_validation_issues` — duplicate, missing, range and membership issues.
- `public.marks_approval_history` — approval/rejection history.
- `public.mark_correction_requests` — correction reason, scope and state.
- `public.course_results` — authoritative published course outcome.
- `public.semester_results` — term GPA, attempted/earned credits and standing.
- `public.cumulative_results` — current CGPA and cumulative credits.
- `public.academic_standing_history` — standing changes with policy version.

## 8. Documents and reporting

- `public.transcript_requests` — request, authorization and idempotency.
- `public.transcript_documents` — generated document and reference metadata.
- `public.transcript_delivery_records` — recipient, attempt and delivery state.
- `ops.hec_report_runs` — report job request and lifecycle.
- `ops.generated_report_files` — Drive file IDs, formats and checksums where available.
- `ops.dashboard_refresh_runs` — dashboard snapshot and refresh result.

## 9. Notifications and operations

- `ops.idempotency_records` — institution, operation, key, request hash and stored result.
- `ops.notification_outbox` — business-generated pending notifications.
- `ops.notification_deliveries` — provider attempts and outcomes.
- `ops.workflow_runs` — workflow execution summary and correlation context.
- `ops.incidents` — root incident and deduplication fingerprint.
- `ops.incident_events` — repeated symptoms, retries and state changes.
- `ops.maintenance_runs` — scheduled maintenance/monitoring history.
- `audit.audit_logs` — append-only business audit records.
- `audit.data_change_events` — optional detailed before/after evidence for sensitive changes.

## 10. Cross-cutting columns

Applicable tables should include:

- UUID primary key;
- `institution_id`;
- `campus_id` where applicable;
- `status`;
- `created_at`, `updated_at`;
- `created_by`, `updated_by`;
- `correlation_id`;
- `idempotency_key` where applicable;
- policy/version reference for decisions that must remain reproducible.

## 11. Critical constraints

Phase 2 must include at least:

- unique institution code;
- unique campus code within institution;
- unique student number within institution;
- controlled uniqueness for CNIC/email according to institution policy;
- one active enrollment per student and offering;
- no duplicate student mark for assessment and batch version;
- one finalization transition per version;
- one published course result per student and offering;
- unique transcript reference number;
- unique idempotency key per institution and operation;
- valid date ranges and non-negative capacity;
- marks between zero and assessment maximum;
- assessment component weights consistent with policy;
- foreign keys that remove ambiguous PostgREST relationships.
