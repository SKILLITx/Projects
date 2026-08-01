# Implementation Sequence

## Phase 0 — Architecture and Assumptions

**Deliverables**

- architecture;
- workflow boundaries;
- diagrams;
- role model;
- entity catalog;
- RPC contract;
- Google Workspace plan;
- repository plan;
- risk register;
- implementation sequence.

**Gate**

User approves the Phase 0 review checklist.

## Phase 1 — Repository and Local Runtime

**Build**

- final directory structure;
- `package.json`;
- `.env.example`;
- `.gitignore`;
- PowerShell startup/stop/environment scripts;
- n8n 2.4.0 compatibility inventory;
- ngrok setup;
- local/public health checks.

**Gate**

- Node.js detected;
- exact n8n version verified;
- port 5678 available;
- n8n starts;
- ngrok starts;
- active public URL identified;
- no secret printed;
- environment validator passes.

## Phase 2 — Supabase Database

**Build order**

1. schemas and extensions;
2. migration ledger/checksums;
3. tenant/configuration tables;
4. identity and authorization;
5. students/curriculum/enrollment;
6. marks/results;
7. documents/reporting;
8. ops/audit;
9. constraints and indexes;
10. RLS;
11. internal functions;
12. public RPC wrappers;
13. fictional seed data;
14. database test suite;
15. ERD and data dictionary.

**Gate**

Migrations apply once on a new project; seeds load; constraints, RLS, role scope, idempotency, rollback, grading, conflict, capacity and waitlist tests pass.

## Phase 3 — Google Workspace and Staff Access

**Build**

- Form specifications and linked Sheet schemas;
- Drive folder plan and setup instructions;
- transcript template;
- HEC demonstration template;
- dashboard template;
- Supabase Auth staff portal;
- credential and authorization guides.

**Gate**

- staff login succeeds;
- invalid/expired token fails;
- institution/campus scope tests pass;
- teacher identity paths pass;
- templates and folders are accessible to configured credentials.

## Phase 4 — Workflows

The business numbering remains 1–10, but implementation order establishes cross-cutting safety infrastructure first.

### Recommended build order

1. **Workflow 10 — Global Error and Incident Handling**
2. **Workflow 8 — Notification Dispatcher**
3. **Workflow 1 — Student Intake and Profile Management**
4. **Workflow 2 — Enrollment Lifecycle**
5. **Workflow 3 — Marks Intake and Validation**
6. **Workflow 4 — Results Approval and Publication**
7. **Workflow 5 — Transcript Delivery**
8. **Workflow 6 — HEC Reporting**
9. **Workflow 7 — Administrative Search and Dashboard**
10. **Workflow 9 — Scheduled Operations and Monitoring**

### Per-workflow gate

- design document complete;
- exact n8n 2.4.0 node compatibility verified;
- portable JSON imports successfully;
- credentials and variables bind;
- static tests pass;
- focused live test passes;
- domain acceptance tests pass;
- failure path creates correct incident;
- `PROJECT_STATE.md` updated.

No next workflow begins until the current workflow is verified or its failure is repaired.

## Phase 5 — Integration and Acceptance

Run:

- static suite;
- full database suite;
- all workflow-specific suites;
- public/authenticated separation tests;
- 30-request enrollment concurrency test;
- transcript generation for five test students with timing;
- full academic-cycle test;
- notification retry/dead-letter test;
- incident deduplication test;
- backup and disposable restore test;
- clean-setup test.

**Gate**

All pilot acceptance criteria pass with evidence, or remaining limitations are explicitly accepted and do not invalidate the controlled pilot.

## Phase 6 — Pilot Handover

Produce:

- final verification report;
- accepted functionality;
- known limitations;
- operating instructions;
- staff onboarding;
- incident response;
- backup/restore procedure;
- credential-binding checklist;
- production migration plan.

## External actions

When external action is unavoidable, request one narrow action at a time. Do not request secrets in chat.
