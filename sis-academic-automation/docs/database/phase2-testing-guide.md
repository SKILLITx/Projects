# Phase 2 Database Testing Guide

## Fast gate

1. Run `scripts/Test-Phase2Package.ps1` locally to verify migration names and immutable checksums.
2. Run `npx supabase db push --dry-run` and confirm only migrations 003–008 are pending.
3. Apply with `npx supabase db push` only after the dry run is clean.
4. Confirm all eight local/remote migration timestamps match with `npx supabase migration list`.
5. Run `scripts/Copy-Phase2Verification.ps1`, paste into Supabase SQL Editor and execute once.

## Expected hosted result

The final result contains `"success": true` and reports:

- 8 verified migrations;
- 56 public business tables;
- 56 RLS-enabled public tables;
- 24 public RPC wrappers;
- 2 institutions;
- 4 campuses;
- 50 students;
- at least 8 courses and 4 sections;
- a rolled-back idempotency test.

## Covered checks

- migration history;
- table and RLS completeness;
- anonymous-access boundary;
- security-definer RPC shape and restricted search path;
- deterministic seed counts;
- tenant foreign-key rejection;
- section capacity;
- timetable conflict detection;
- grade resolution;
- stable RPC response;
- database-enforced idempotency;
- transactional rollback.

Later Phase 5 tests add concurrency, full workflow integration, backup/restore and clean-setup verification.
