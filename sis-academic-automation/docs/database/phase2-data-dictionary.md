# Phase 2 Data Dictionary

This catalog covers 69 tables created by the ordered Phase 2 migrations. The complete column-level dictionary is `database/schema/data-dictionary.csv`.

## Audit

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `audit.audit_logs` | Private business-operation audit evidence. | 14 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `audit.data_change_events` | Stores data change events records for the academic operations model. | 10 | `20260717000600_phase2_documents_reporting_operations.sql` |

## Curriculum & scheduling

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `public.assessment_components` | Stores assessment components records for the academic operations model. | 11 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.assessments` | Stores assessments records for the academic operations model. | 14 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.course_equivalencies` | Stores course equivalencies records for the academic operations model. | 6 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.course_offerings` | Stores course offerings records for the academic operations model. | 14 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.course_prerequisites` | Stores course prerequisites records for the academic operations model. | 10 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.courses` | Stores courses records for the academic operations model. | 13 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.rooms` | Stores rooms records for the academic operations model. | 9 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.section_schedules` | Stores section schedules records for the academic operations model. | 12 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.sections` | Stores sections records for the academic operations model. | 12 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.teacher_assignments` | Stores teacher assignments records for the academic operations model. | 12 | `20260717000300_phase2_academic_configuration_curriculum.sql` |

## Enrollment

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `public.enrollment_decisions` | Stores enrollment decisions records for the academic operations model. | 12 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.enrollment_request_items` | Stores enrollment request items records for the academic operations model. | 12 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.enrollment_requests` | Enrollment request envelope and durable outcome. | 17 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.enrollments` | Accepted student-to-section enrollment records. | 14 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.prerequisite_evidence` | Stores prerequisite evidence records for the academic operations model. | 8 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.timetable_conflict_evidence` | Stores timetable conflict evidence records for the academic operations model. | 9 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.waitlist_entries` | Ordered waitlist state for full offerings. | 13 | `20260717000400_phase2_students_documents_enrollment.sql` |

## Identity & authorization

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `audit.authorization_events` | Stores authorization events records for the academic operations model. | 11 | `20260717000200_phase2_identity_and_authorization.sql` |
| `public.campus_assignments` | Explicit campus scope for staff roles. | 11 | `20260717000200_phase2_identity_and_authorization.sql` |
| `public.permission_grants` | Optional allow/deny permission overrides. | 13 | `20260717000200_phase2_identity_and_authorization.sql` |
| `public.role_assignments` | Time-bounded institution-scoped staff roles. | 11 | `20260717000200_phase2_identity_and_authorization.sql` |
| `public.staff_profiles` | Staff identity linked to Supabase Auth. | 10 | `20260717000200_phase2_identity_and_authorization.sql` |
| `public.student_auth_links` | Stores student auth links records for the academic operations model. | 6 | `20260717000400_phase2_students_documents_enrollment.sql` |

## Institution & configuration

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `public.academic_standing_rules` | Stores academic standing rules records for the academic operations model. | 11 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.academic_years` | Stores academic years records for the academic operations model. | 11 | `20260717000100_phase2_foundation_and_tenancy.sql` |
| `public.campuses` | Institution-owned campuses and campus-level scope. | 13 | `20260717000100_phase2_foundation_and_tenancy.sql` |
| `public.departments` | Stores departments records for the academic operations model. | 9 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.enrollment_periods` | Stores enrollment periods records for the academic operations model. | 13 | `20260717000100_phase2_foundation_and_tenancy.sql` |
| `public.enrollment_policies` | Stores enrollment policies records for the academic operations model. | 17 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.grade_scales` | Stores grade scales records for the academic operations model. | 11 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.grading_policies` | Stores grading policies records for the academic operations model. | 14 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.hec_report_settings` | Stores hec report settings records for the academic operations model. | 10 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.institution_settings` | Versioned institution-wide operational configuration. | 17 | `20260717000100_phase2_foundation_and_tenancy.sql` |
| `public.institutions` | Tenant institution master record and academic-model selection. | 12 | `20260717000100_phase2_foundation_and_tenancy.sql` |
| `public.notification_settings` | Stores notification settings records for the academic operations model. | 11 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.programs` | Stores programs records for the academic operations model. | 14 | `20260717000300_phase2_academic_configuration_curriculum.sql` |
| `public.terms` | Stores terms records for the academic operations model. | 14 | `20260717000100_phase2_foundation_and_tenancy.sql` |
| `public.transcript_settings` | Stores transcript settings records for the academic operations model. | 11 | `20260717000300_phase2_academic_configuration_curriculum.sql` |

## Marks & results

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `public.academic_standing_history` | Stores academic standing history records for the academic operations model. | 12 | `20260717000500_phase2_marks_results.sql` |
| `public.course_results` | Calculated course grade and grade point. | 21 | `20260717000500_phase2_marks_results.sql` |
| `public.cumulative_results` | Program-level CGPA and standing. | 16 | `20260717000500_phase2_marks_results.sql` |
| `public.mark_correction_requests` | Stores mark correction requests records for the academic operations model. | 18 | `20260717000500_phase2_marks_results.sql` |
| `public.marks_approval_history` | Stores marks approval history records for the academic operations model. | 9 | `20260717000500_phase2_marks_results.sql` |
| `public.marks_batch_files` | Stores marks batch files records for the academic operations model. | 10 | `20260717000500_phase2_marks_results.sql` |
| `public.marks_batches` | Versioned class marks submissions and lifecycle. | 18 | `20260717000500_phase2_marks_results.sql` |
| `public.marks_validation_issues` | Stores marks validation issues records for the academic operations model. | 11 | `20260717000500_phase2_marks_results.sql` |
| `public.semester_results` | Term GPA and standing. | 18 | `20260717000500_phase2_marks_results.sql` |
| `public.student_marks` | Assessment-level student marks. | 12 | `20260717000500_phase2_marks_results.sql` |

## Operations

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `ops.dashboard_refresh_runs` | Stores dashboard refresh runs records for the academic operations model. | 10 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.generated_report_files` | Stores generated report files records for the academic operations model. | 10 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.hec_report_runs` | Stores hec report runs records for the academic operations model. | 18 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.idempotency_records` | Database-enforced request replay protection. | 12 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.incident_events` | Stores incident events records for the academic operations model. | 10 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.incidents` | Deduplicated operational incidents. | 20 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.maintenance_runs` | Stores maintenance runs records for the academic operations model. | 8 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.notification_deliveries` | Stores notification deliveries records for the academic operations model. | 13 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.notification_outbox` | Transactional notification work queue. | 24 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `ops.workflow_runs` | Durable n8n workflow execution records. | 17 | `20260717000600_phase2_documents_reporting_operations.sql` |

## Students & documents

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `public.document_requirements` | Stores document requirements records for the academic operations model. | 10 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.student_contacts` | Stores student contacts records for the academic operations model. | 12 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.student_documents` | Stores student documents records for the academic operations model. | 16 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.student_profile_requests` | Idempotent intake/update request evidence. | 14 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.student_program_registrations` | Stores student program registrations records for the academic operations model. | 15 | `20260717000400_phase2_students_documents_enrollment.sql` |
| `public.students` | Canonical tenant-scoped student identity. | 15 | `20260717000400_phase2_students_documents_enrollment.sql` |

## Transcripts

| Schema.table | Purpose | Columns | Migration |
|---|---|---:|---|
| `public.transcript_delivery_records` | Stores transcript delivery records records for the academic operations model. | 11 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `public.transcript_documents` | Stores transcript documents records for the academic operations model. | 10 | `20260717000600_phase2_documents_reporting_operations.sql` |
| `public.transcript_requests` | Idempotent transcript-generation requests. | 18 | `20260717000600_phase2_documents_reporting_operations.sql` |

