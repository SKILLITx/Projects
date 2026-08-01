# Phase 4 Wave 1 Construction Validation

Validated before packaging:

- complete migrations 001–009 execute in order in a PostgreSQL-compatible runtime;
- hosted verification SQL executes as one rolled-back transaction and returns `success=true` for nine checks;
- student and enrollment wrappers return the original completed result when the same idempotency key is replayed with a new correlation ID;
- Cambridge-school submissions enforce guardian data while complete school submissions succeed;
- duplicate student-document codes are rejected before core side effects;
- a new university student with missing required documents receives a stable enrollment rejection;
- a documented student receives the requested valid section allocation;
- duplicate course codes are rejected before enrollment side effects;
- a forbidden section fallback returns `ENROLLMENT_FALLBACK_NOT_ALLOWED` and leaves zero enrollment rows;
- notification begin-attempt replay returns `should_send=false`;
- notification finalization is idempotent and creates one delivery row;
- preferred-section arrays preserve blank positions so course/section ordering remains aligned;
- completed queue rows are skipped without being overwritten;
- three workflow JSON files parse;
- every Code node and n8n expression compiles;
- every node type and version exists in n8n 2.4.0 source definitions;
- every node has purpose/input/output/error notes;
- no Execute Command nodes exist;
- no credential IDs, Supabase URLs, keys or Google IDs are hardcoded;
- workflows call only public RPC routes;
- success and error execution payload persistence is disabled for personal-data workflows;
- the merged migration ledger contains nine matching SHA-256 checksums.
