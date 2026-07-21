# Phase 4 Wave 1 Workflow Catalog

| File | Business domain | Trigger | Primary RPC |
|---|---|---|---|
| `01-student-intake.json` | Student intake and profile management | Google Sheets row added | `rpc_submit_student_profile_from_form` |
| `02-enrollment-lifecycle.json` | Course/subject enrollment | Google Sheets row added | `rpc_submit_enrollment_from_form` |
| `08-notification-dispatcher.json` | Outbox delivery | Every minute | claim, begin and record notification RPCs |

All three imports are inactive and contain no credential IDs.
