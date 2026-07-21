# Workflow 07 Acceptance Guide

## Preconditions

1. The complete Workflow 07 migration has been applied and `database/queries/workflow07-verification.sql` reports PASS.
2. `workflows/07-admin-dashboard.json` has been imported into n8n 2.4.0.
3. Every node named `Log ...` is bound to the existing credential `SIS Supabase Service Role`.
4. `SUPABASE_URL` and `SUPABASE_ANON_KEY` are available to the n8n runtime.
5. The workflow is active.
6. `portal/config.local.js` contains the current public n8n/ngrok base URL and only the Supabase anon browser key.
7. The local portal and n8n/ngrok runtime are healthy.

Do not paste passwords, access tokens, refresh tokens or service-role values into chat, command history or evidence files.

## Static suite

Run from the installed repository:

```powershell
& ".\scripts\Test-Workflow07Static.ps1"
```

Expected final line:

```text
SIS 07 STATIC VALIDATION: PASS
```

The suite validates JSON structure, exact workflow identity/routes, explicit response nodes, supported n8n 2.4.0 node families and versions, connection integrity, code parsing, credential boundaries, public-RPC URLs, UUID validation, portal controls, identity masking and required deliverables.

## Database contract and migration sequence

1. Copy and run the read-only contract snapshot:

```powershell
& ".\scripts\Copy-Workflow07ContractSnapshot.ps1"
```

2. Review the existing function signatures and relation/index metadata.
3. Copy and run the immutable complete migration:

```powershell
& ".\scripts\Copy-Workflow07Migration.ps1"
```

4. Copy and run compact verification:

```powershell
& ".\scripts\Copy-Workflow07Verification.ps1"
```

5. Run `database/tests/workflow07-admin-dashboard.sql` in Supabase SQL Editor. It is transactional and rolls back its temporary role-status changes.

## Positive acceptance

Run:

```powershell
& ".\scripts\Run-Workflow07Acceptance.ps1" -Mode Positive
```

The script securely prompts for the current pilot staff password, signs in through Supabase Auth and does not print or persist the token. It checks:

- exact `DMU-0001` search;
- partial name search;
- email search;
- exact fictional identity-reference search with masked-only output;
- zero-result success;
- DMU/ISB dashboard shape and numeric GPA/CGPA;
- published `B` grade presence.

Expected final line:

```text
SIS 07 POSITIVE ACCEPTANCE: PASS
```

A sanitized evidence JSON file is written under `evidence/` with HTTP status, correlation ID and n8n execution ID.

## Bundled negative suite

Run:

```powershell
& ".\scripts\Run-Workflow07Acceptance.ps1" -Mode Negative
```

The live bundle checks missing, invalid and expired authentication; invalid institution/campus UUIDs; empty and one-character searches; unsupported search type; identity masking; zero matches; and an empty dashboard scope when an authorized empty fixture exists.

Teacher-only denial is also tested transactionally in `database/tests/workflow07-admin-dashboard.sql`. A live teacher-only actor and an out-of-scope limited actor are not fabricated by this package. Temporary Supabase outage behavior requires a controlled fault-injection window and is recorded as a coverage note rather than falsely reported as executed.

Expected final line when all runnable cases pass:

```text
SIS 07 NEGATIVE ACCEPTANCE: PASS
```

## Portal acceptance

After the automated suite:

1. Open the portal and reuse the current authenticated session.
2. Confirm institution/campus selectors show names and codes.
3. Search `DMU-0001` and confirm no internal UUID is shown.
4. Search the fictional identity fixture and confirm only a masked value appears.
5. Refresh the dashboard and confirm cards, grade distribution and capacity render.
6. Confirm the browser-visible output never shows an access token.
7. Capture one portal screenshot and store it under `evidence/`.

## Freeze rule

Do not freeze Workflow 07 until migration verification, import, activation, positive suite, bundled negative suite, database test, portal acceptance and durable workflow-run evidence have all passed. After that, keep the complete workflow active, deactivate older Workflow 07 variants without deleting them, and change it only for a reproduced regression.
