# Phase 2 Accelerated Package Validation Evidence

Generated: 2026-07-16T21:44:05+00:00

## Static SQL parse

All six new migrations were parsed successfully with a PostgreSQL parser:

- `20260717000300_phase2_academic_configuration_curriculum.sql` — 95 top-level statements parsed.
- `20260717000400_phase2_students_documents_enrollment.sql` — 106 top-level statements parsed.
- `20260717000500_phase2_marks_results.sql` — 61 top-level statements parsed.
- `20260717000600_phase2_documents_reporting_operations.sql` — 78 top-level statements parsed.
- `20260717000700_phase2_public_rpc_contract.sql` — 84 top-level statements parsed.
- `20260717000800_phase2_demo_seed.sql` — 54 top-level statements parsed.

## PostgreSQL-compatible execution check

The complete 001–008 chain was executed from an empty PostgreSQL-compatible in-memory database with:

- stub `auth.users`, `auth.uid()` and Supabase roles;
- a build-only SHA-256-compatible-length digest shim because the test runtime did not provide `pgcrypto`;
- no Docker and no project secrets.

Observed results:

- all eight migrations executed in order;
- seed loaded 2 institutions, 4 campuses, 50 students, 10 courses and 9 sections;
- all 56 public tables had RLS enabled;
- all 24 RPC wrappers existed, returned JSONB, were security-definer functions and used a restricted search path;
- full-section capacity returned zero;
- a known overlapping schedule returned a conflict;
- score 86 resolved to grade A / 4.00;
- repeated student-profile RPC submission returned the identical durable result.

## Repairs made during validation

- Added the missing composite tenant key on `enrollment_periods` required by later scoped foreign keys.
- Cast enum values explicitly across seed `UNION ALL` branches.
- Replaced unsupported UUID aggregation with deterministic latest-row selection in GPA/CGPA recalculation.

## Limitation

This construction-time execution check is not a substitute for the hosted Supabase dry run, migration application, migration-history comparison and hosted verification suite. Those remain the completion gate.
