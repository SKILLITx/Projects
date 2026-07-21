# Workflow 07 — Administrative Search and Basic Dashboard

## Status

Generated for the controlled local pilot. Static validation is required before import; hosted migration, activation and live acceptance remain external verification steps.

## Workflow identity

- n8n name: `SIS 07 — Administrative Search and Basic Dashboard — Complete`
- Portable export: `workflows/07-admin-dashboard.json`
- Runtime: n8n `2.4.0`
- Credential used only for durable run logging: `SIS Supabase Service Role`

## Operations

### Student search

`POST /webhook/staff/rpc_search_students`

The branch validates the request and bearer-token shape, calls the Supabase Auth user endpoint, forwards the verified staff JWT to `public.rpc_search_students(p_request jsonb)`, normalizes the response, records a durable workflow run, and returns an explicit webhook response.

Supported search types:

- `auto`
- `student_number`
- `name`
- `email`
- `identity_reference`

Search is institution/campus scoped, bounded to 25 rows, stably ordered and zero-safe. Exact identity searches compare a PostgreSQL hash and return only a masked value. The full submitted identity value is not echoed in the public response.

### Dashboard snapshot

`POST /webhook/staff/rpc_get_dashboard_snapshot`

The branch follows the same authentication model and calls `public.rpc_get_dashboard_snapshot(p_request jsonb)`. PostgreSQL performs the aggregation; n8n does not fetch and aggregate raw academic rows.

The response includes:

- selected institution, campus and resolved term names/codes;
- student, enrollment, waitlist, marks, GPA/CGPA, transcript, notification and incident metrics;
- grade distribution;
- course/section capacity;
- visible term choices;
- zero values and empty arrays when no rows exist.

## Authorization

The public business RPCs execute only for the `authenticated` database role and derive identity from `auth.uid()`. Supported project roles are:

- `super_administrator`;
- `registrar_admin` (the repository's existing enum for registrar/administrator);
- `campus_administrator` within assigned campuses.

A teacher-only actor is denied. A staff member with both an authorized administrative role and a teacher role is accepted because authorization checks for any active allowed role.

The browser-supplied role, institution name and campus name are never trusted as authorization. Internal institution/campus IDs are carried in authenticated request context but the portal displays only names and codes.

## Credential boundary

Business RPC nodes use:

- Supabase anon key from the n8n environment as the API key;
- the verified staff bearer token as `Authorization`.

They do not bind the service-role credential. The existing `SIS Supabase Service Role` credential is bound only to `rpc_log_workflow_run` nodes so a logging failure cannot become browser authorization.

## Database migration

The earlier migration `20260721000100_phase4_workflow07_admin_search_dashboard.sql` already existed and remains immutable. The complete repair is:

`database/migrations/20260721000200_phase4_workflow07_admin_search_dashboard_complete.sql`

It replaces the two public RPC definitions, applies exact grants, adds only reviewed search indexes and stores a hash-only fictional identity fixture for `DMU-0001` when that synthetic record has no hash.

## Portal integration

The existing portal is updated in place. It preserves authentication, role/scope display and existing administrative actions. Workflow 07 adds:

- human-readable search-type controls and Clear action;
- no student, institution, campus, program or term UUID entry;
- readable student result rows;
- twelve dashboard metric cards;
- grade and capacity tables;
- sanitized support details that remove tokens, raw identities and internal record identifiers.

`portal/config.local.js` is never included in the package or overwritten by the installer. Its `n8nBaseUrl` must hold the current ngrok base for the live session.

## Expected performance

Controlled-pilot targets:

- student search usually under 3 seconds;
- dashboard snapshot usually under 5 seconds.

These are not production guarantees.

## Deferred scope

- Google Sheets dashboard refresh;
- scheduled dashboard refresh;
- management workbook;
- advanced charts and executive BI;
- CSV/Excel dashboard export;
- hosted production availability, monitoring and high availability.
