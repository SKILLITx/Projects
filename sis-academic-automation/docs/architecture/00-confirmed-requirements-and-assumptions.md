# Confirmed Requirements and Assumptions

## 1. Objective

Build a reusable academic operations system that reduces repeated manual entry and supports:

- student intake and profile management;
- eligibility and prerequisite verification;
- course or subject enrollment;
- section allocation, capacity checks and waitlisting;
- timetable-conflict detection;
- marks submission and validation;
- results approval, grading, GPA and CGPA;
- transcript generation and delivery;
- HEC enrollment reporting;
- administrative search and dashboards;
- notifications, monitoring, incidents, audit history and backups.

The system must support both university credit-hour models and school/Cambridge subject-based models without hardcoding one institution, campus, grading scale or academic structure.

## 2. Confirmed deployment boundary

The first implementation is a **controlled pilot** using local n8n, SQLite metadata, a dynamic or optional reserved ngrok URL and a local Windows computer.

It must not be represented as hosted production. Production readiness requires a later migration to hosted n8n, PostgreSQL metadata, stable HTTPS, managed backups, centralized monitoring, stronger secret management and production email configuration.

## 3. Confirmed technology choices

- Windows 11
- Windows PowerShell 5.1-compatible commands
- Node.js
- n8n 2.4.0 installed through npm
- n8n default SQLite metadata database
- a completely new Supabase project
- Supabase PostgreSQL as the system of record
- Supabase Auth for authenticated staff operations
- ngrok for public webhook exposure
- Google Forms, Sheets, Drive, Docs and Gmail
- no Docker
- no Execute Command nodes
- small Code nodes only where native nodes are insufficient

## 4. Resolved contradictions

### 4.1 Original Airtable design versus rebuilt Supabase design

**Decision:** Airtable is excluded. The original brief is treated as a domain and problem statement. Supabase PostgreSQL is the sole academic system of record.

### 4.2 Five-day intern sprint versus pilot-ready implementation

**Decision:** The five-day plan is not a valid implementation schedule for the rebuilt scope. It is treated as an MVP demonstration reference only. The actual work follows Phases 0–6 with verification gates.

### 4.3 Student role versus staff-only authentication requirement

**Decision:** Student is both a domain role and an optional authenticated role. Public Google Forms remain the default pilot interface. A student may receive an Auth identity only when an institution enables authenticated student access and links `auth.users` to the student record.

### 4.4 Teacher forms versus strong identity assurance

**Decision:** A teacher may submit through:

1. a Google Form restricted to approved institutional Google accounts, with captured email checked against the teacher assignment; or
2. the authenticated staff portal when domain-restricted Google Forms are unavailable.

An unrestricted public marks form is not acceptable.

### 4.5 HEC reporting requirement versus missing official template

**Decision:** The system will generate a clearly labelled **demonstration HEC enrollment report** until the institution supplies an official current template and confirms its required fields.

### 4.6 RLS versus server-side service-role access

**Decision:** Browser clients never receive the service-role key. Authenticated staff operations use the user's Supabase access token wherever practical so `auth.uid()` and RLS remain meaningful. Service-role access is limited to n8n server-side processes that require elevated access and may call only tightly scoped, audited RPC wrappers.

## 5. High-risk assumptions

| Assumption | Risk | Architectural response |
|---|---|---|
| n8n 2.4.0 supports every proposed native node/action | Import or runtime failure | Verify exact installed node versions and exported JSON shape before Workflow 1 |
| Institution has Google Workspace accounts for teachers | Weak identity on marks forms | Use authenticated portal fallback |
| Dynamic ngrok URL is acceptable in a pilot | URL changes break webhooks/OAuth | Detect active URL and provide a controlled update procedure |
| Gmail API acceptance equals delivery | False delivery confidence | Store provider message ID and delivery attempt; do not claim inbox delivery |
| One configuration model can represent university and Cambridge rules | Over-generalization | Use versioned policies, explicit academic model and model-specific validation |
| Local Windows host remains available | Workflow downtime | Pilot operating procedure, restart scripts, health checks and later hosted migration |
| Institution can provide authoritative academic rules | Incorrect grading/enrollment | Configuration approval checklist before live pilot |
| Public Google Form data is trustworthy | Spoofing and malformed data | Server-side validation, duplicate checks, rate control and sanitized responses |
| Service role can be used broadly because it is server-side | RLS bypass and excessive privilege | Minimum RPC surface, audit logs and no direct browser exposure |

## 6. Architecture principles

1. Supabase is the source of truth; Google Sheets are intake or reporting surfaces, never authoritative academic storage.
2. Business invariants are enforced in PostgreSQL constraints and transactions.
3. n8n orchestrates external systems; it does not own academic rules.
4. All institution-specific behaviour is configuration-driven and versioned.
5. Public and authenticated operations use separate trust paths.
6. Each business request has a correlation ID and an idempotency key.
7. Notification sending is decoupled through a database outbox.
8. Public responses are sanitized; diagnostics are stored privately.
9. Temporary failures are retried by one owner with bounded backoff.
10. Readiness is proved by durable outcomes and recorded evidence, not by valid JSON alone.
