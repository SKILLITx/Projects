# Production Migration Plan

## Phase 1 - Hosting foundation

- Move n8n from local Windows to a supported hosted environment.
- Replace local SQLite metadata with managed PostgreSQL for n8n.
- Replace ngrok with a permanent HTTPS domain.
- Host the staff portal behind authenticated HTTPS.
- Separate development, staging, and production configuration.

## Phase 2 - Security and operations

- Use managed secret storage and rotate all pilot credentials.
- Establish least-privilege access reviews.
- Add centralized logging and alert routing.
- Define formal incident response, retention, backup, and disaster-recovery policies.
- Add automated backup scheduling and periodic restore drills.

## Phase 3 - Deferred workflows

- Implement Workflow 06 - HEC Enrollment Reporting.
- Implement Workflow 10 - Global Error Handler with recursive redaction, stable fingerprints, deduplication, cooldown, and bounded retries.

## Phase 4 - Scale and quality

- Load-test enrollment, marks, results, transcript, and notification operations.
- Improve portal accessibility and responsive behavior.
- Add staging acceptance and release gates.
- Define service-level objectives, support ownership, and escalation paths.

The system must not be described as production-ready until these requirements have been completed and verified.
