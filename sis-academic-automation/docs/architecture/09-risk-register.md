# Risk Register

Scales:

- Likelihood: Low, Medium, High
- Impact: Low, Medium, High, Critical

| ID | Risk | Likelihood | Impact | Mitigation | Verification gate |
|---|---|---|---|---|---|
| R-001 | n8n 2.4.0 node parameters differ from assumed exports | Medium | High | Inspect installed node types and create exports from compatible schema | Before first workflow JSON |
| R-002 | Dynamic ngrok URL invalidates webhooks or OAuth redirect | High | High | Startup detection, controlled config update and optional reserved domain | Phase 1 runtime test |
| R-003 | Local Windows host or internet becomes unavailable | Medium | High | Health checks, restart procedure, pilot support window, hosted migration plan | Pilot checklist |
| R-004 | Service-role key is exposed or overused | Low | Critical | Server-only storage, never browser code, named RPCs, audit and secret scanning | Static/security tests |
| R-005 | RLS policy leaks another institution's data | Medium | Critical | Deny-by-default policies, role/campus tests and adversarial cross-tenant tests | Phase 2 RLS gate |
| R-006 | Teacher identity can be spoofed through an unrestricted Form | Medium | Critical | Domain-restricted Form or authenticated portal; verify email and assignment | Phase 3 authorization gate |
| R-007 | Concurrent enrollment exceeds section capacity | Medium | Critical | Transactional locking, unique constraints and 30-request concurrency test | Phase 5 load gate |
| R-008 | Idempotency key is generated inconsistently across adapters | Medium | High | Standard source key algorithm, request hash and database unique constraint | Per-workflow acceptance |
| R-009 | University and Cambridge rules are forced into one invalid model | Medium | High | Explicit academic model, versioned policies and model-specific validation | Phase 2 configuration tests |
| R-010 | Ambiguous foreign keys break PostgREST relationships | Medium | High | Explicit FK names, no implicit join dependency, RPC result models | Static/database tests |
| R-011 | Empty RPC result stops downstream n8n processing | Medium | High | Every RPC returns one JSON object with explicit empty arrays/objects | RPC contract tests |
| R-012 | Permanent failures are retried repeatedly | Medium | High | Stable error classification, one retry owner, bounded attempts, dead letter | Notification/error tests |
| R-013 | Error alert failure prevents incident persistence | Low | High | Persist incident first, create outbox alert second | Error acceptance test |
| R-014 | Gmail provider acceptance is mistaken for final delivery | High | Medium | Record accepted/sent state accurately and document delivery limitation | Handover review |
| R-015 | Google API quota or temporary outage blocks documents | Medium | Medium | Durable job state, bounded retry and resumable generation | Transcript/report tests |
| R-016 | Official HEC format is unavailable or changes | High | High | Clearly labelled demonstration template; institution approval required | Pre-pilot requirements |
| R-017 | Sensitive data is copied into logs or evidence | Medium | Critical | Sanitization, redaction, no raw headers/tokens, evidence review | Static/security tests |
| R-018 | Backup exists but cannot be restored | Medium | Critical | Checksums and disposable restore verification | Phase 5 restore gate |
| R-019 | Google response Sheet is treated as authoritative state | Medium | High | Supabase-only source of truth and reconciliation checks | Architecture/code review |
| R-020 | Workflow fragmentation recreates the failed 25-workflow design | Medium | High | Ten domain boundaries, review required for any new workflow | Architecture governance |
| R-021 | Staff policy configuration is incomplete or wrong | Medium | Critical | Institution configuration sign-off and seeded validation scenarios | Pre-pilot gate |
| R-022 | Uploaded marks contain malware or unsupported files | Low | High | MIME/extension/size checks, controlled Drive folder, reject unexpected formats | Marks workflow tests |
| R-023 | Public Forms are abused or spammed | Medium | Medium | Server validation, rate controls where practical, duplicate detection | Public intake tests |
| R-024 | Student identity is insufficient for transcript release | Medium | Critical | Institution-defined verification rules and manual review for uncertain requests | Transcript authorization test |
