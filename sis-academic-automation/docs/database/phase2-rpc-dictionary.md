# Phase 2 RPC Dictionary

The public contract contains 24 JSON-in/JSON-out RPC wrappers. Each accepts `p_request jsonb`, returns one `jsonb` object, uses a restricted search path and has explicit role grants.

| RPC | Operation | Caller | Idempotent | Purpose |
|---|---|---|---|---|
| `rpc_apply_scheduled_maintenance` | `operations.maintenance.apply` | service_role | Yes | Release stale claims, dead-letter exhausted work and supersede stale drafts. |
| `rpc_claim_notifications` | `notification.claim` | service_role | No | Claim a bounded batch using row locks and skip-locked semantics. |
| `rpc_create_hec_report_run` | `hec.report.create` | authenticated registrar/admin | Yes | Create an idempotent HEC reporting run. |
| `rpc_create_transcript_request` | `transcript.request` | authenticated student/staff or service_role | Yes | Create an authorized transcript request and return one stable object. |
| `rpc_decide_enrollment` | `enrollment.decision` | authenticated admin | Yes | Record an authorized manual enrollment decision. |
| `rpc_decide_mark_correction` | `marks.correction.decision` | authenticated registrar/admin | Yes | Approve or reject and apply a mark correction. |
| `rpc_decide_marks_batch` | `marks.batch.decision` | authenticated registrar/admin | Yes | Approve or reject a finalized marks batch. |
| `rpc_finalize_marks_batch` | `marks.batch.finalize` | teacher or service_role | Yes | Finalize one draft once after validation. |
| `rpc_get_dashboard_snapshot` | `dashboard.snapshot.get` | authenticated authorized staff or service_role | No | Return one operational and academic dashboard snapshot. |
| `rpc_get_hec_enrollment_data` | `hec.report.data.get` | authenticated registrar/admin or service_role | No | Return institution-scoped enrollment reporting data. |
| `rpc_get_operations_snapshot` | `operations.snapshot.get` | authenticated admin or service_role | No | Return workflow, incident and notification health metrics. |
| `rpc_get_transcript_model` | `transcript.model.get` | authenticated authorized caller or service_role | No | Return one complete transcript JSON model. |
| `rpc_log_workflow_run` | `workflow.run.log` | service_role | Yes | Create or update durable n8n execution evidence. |
| `rpc_promote_waitlist` | `enrollment.waitlist.promote` | authenticated admin or service_role | Yes | Promote the next valid waitlist entry under locking and capacity checks. |
| `rpc_publish_results` | `results.publish` | authenticated registrar/admin | Yes | Calculate course grades, GPA, CGPA and standing, then publish results. |
| `rpc_record_generated_report` | `report.file.record` | service_role | Yes | Record generated report files and notification work. |
| `rpc_record_incident` | `incident.record` | service_role | Yes | Create or deduplicate an operational incident. |
| `rpc_record_notification_attempt` | `notification.delivery.record` | service_role | Yes | Record provider response and update bounded retry/dead-letter state. |
| `rpc_record_transcript_document` | `transcript.document.record` | service_role | Yes | Record generated transcript metadata and delivery work. |
| `rpc_request_mark_correction` | `marks.correction.request` | teacher or service_role | Yes | Open a controlled correction request. |
| `rpc_search_students` | `student.admin.search` | authenticated authorized staff | No | Return bounded institution/campus-scoped student search results. |
| `rpc_submit_enrollment_request` | `enrollment.submit` | service_role | Yes | Evaluate period, student state, documents, prerequisites, load, schedule, capacity, fallback and waitlist transactionally. |
| `rpc_submit_marks_batch` | `marks.batch.submit` | teacher or service_role | Yes | Create a versioned marks draft and validate class membership and ranges. |
| `rpc_submit_student_profile` | `student.profile.submit` | service_role | Yes | Create or update a student profile, program registration, documents, audit record and outbox notification. |

The machine-readable catalog is `database/schema/rpc-dictionary.csv`.
