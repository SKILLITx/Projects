# Final Architecture

## 1. Architectural style

The system is a modular, database-centred automation platform:

- **Supabase PostgreSQL** owns configuration, academic records, authorization assignments, transactions, idempotency, audit data and operational state.
- **n8n** validates adapters, orchestrates RPC calls and integrates Google Workspace.
- **Google Workspace** supplies low-friction intake, document generation, file storage, dashboard presentation and email delivery.
- **A minimal staff portal** provides authenticated administrative actions without becoming a large application.
- **ngrok** exposes selected local n8n webhook endpoints during a controlled pilot.

## 2. Logical layers

### Layer A — User interaction

- Public student Google Forms
- Restricted teacher Google Forms
- Minimal authenticated staff portal
- Administrator-triggered Google Sheets or portal actions

### Layer B — Intake adapters

- Google Forms linked response Sheets
- Google Sheets Trigger if verified on n8n 2.4.0
- Schedule-based polling fallback
- Authenticated n8n webhooks for portal requests
- Webhook response sanitizer

This layer converts external data into the standard request envelope. It must not calculate grades, allocate capacity or make authorization decisions.

### Layer C — Orchestration

n8n business-domain workflows:

1. Student Intake and Profile Management
2. Course and Subject Enrollment Lifecycle
3. Marks Intake and Validation
4. Results Approval and Publication
5. Transcript Request, Generation and Delivery
6. HEC Enrollment Reporting
7. Administrative Search and Dashboard
8. Notification Dispatcher
9. Scheduled Operations and Monitoring
10. Global Error and Incident Handling

### Layer D — Public database API

The `public` schema exposes:

- RLS-protected business tables that genuinely require direct authenticated access;
- stable public RPC wrappers;
- public-safe read views only when a view is clearer than an RPC.

n8n never calls `app`, `audit`, `ops` or `reporting` schemas through PostgREST.

### Layer E — Internal database logic

The `app` schema contains transactional helper functions and complex business rules, including:

- policy resolution;
- prerequisite evaluation;
- schedule-overlap detection;
- capacity locking;
- waitlist placement and promotion;
- marks validation;
- grade and GPA calculations;
- transcript model assembly;
- report model assembly.

The `audit` schema preserves immutable audit history.

The `ops` schema stores workflow runs, notifications, incidents, delivery attempts, report runs and idempotency operations.

The `reporting` schema contains internal reporting views or materialized models. It is not a public API.

### Layer F — External output

- Gmail for notifications and document delivery
- Google Docs for transcript templates
- Google Drive for generated files and uploaded marks
- Google Sheets for HEC demonstration reports and dashboards

## 3. Trust boundaries

### Public student path

`Google Form → linked Sheet → n8n → server-side validation → public RPC using trusted server credential → transaction`

Controls:

- source submission key;
- input schema validation;
- institution/campus validation;
- rate control where practical;
- duplicate detection;
- database idempotency;
- sanitized response;
- no direct browser-to-service-role access.

### Teacher path

Preferred:

`Restricted Google Form → linked Sheet → n8n → captured Google account email → teacher assignment check → marks RPC`

Fallback:

`Staff portal → Supabase Auth → access token → n8n webhook → token validation → user-token RPC`

### Authenticated administrator path

`Portal → Supabase Auth → access token → n8n webhook → validate user → invoke RPC with user token → auth.uid()-based authorization → transaction`

The portal contains only the Supabase URL and anon key. The service-role key remains in n8n credentials or server environment configuration.

### Elevated server path

Scheduled dispatchers, monitoring and trusted public-form processors may require service-role access. They must use only named RPC wrappers and write operational audit records.

## 4. Transaction boundaries

A transaction should include all database state that must succeed or fail together. Examples:

- enrollment request, decision, section allocation or waitlist record, decision history and notification outbox insert;
- marks finalization and version state transition;
- results approval, course-result upsert, GPA/CGPA recalculation and publication outbox records;
- transcript request creation and idempotency reservation.

Google API calls are not placed inside database transactions. The database first records an outbox or job state; the dispatcher or document workflow performs the external action and records the outcome.

## 5. Consistency and concurrency

- Section capacity is enforced under row-level locking or an equivalent transactional allocation strategy.
- Unique constraints prevent duplicate enrollments, finalizations, publications and deliveries.
- Waitlist order uses a deterministic sequence such as request time plus a monotonic identifier.
- Idempotency is enforced by unique keys scoped to institution and operation.
- Recalculations use deterministic upserts, not blind inserts.
- Every RPC returns one JSON object even when no matching business record exists.

## 6. Readiness boundaries

### Portfolio/demo

A coherent demonstration may run with fictional data and manual operator support.

### Controlled pilot

Requires clean setup, verified migrations, RLS tests, workflow imports, credential binding, domain acceptance tests, concurrency test, complete academic-cycle test, backup and restore verification and documented limitations.

### Hosted production

Requires a later infrastructure migration and operational controls not provided by local npm n8n plus ngrok.
