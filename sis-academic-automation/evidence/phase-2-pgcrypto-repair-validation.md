# Phase 2 pgcrypto Repair Evidence

- Failure layer: database migration compilation.
- First incorrect state: unqualified `digest(...)` while the function existed in Supabase's `extensions` schema.
- Failed migration: `20260717000700_phase2_public_rpc_contract.sql`.
- Transaction result: migration 007 rolled back; migration 008 did not run.
- Repair: qualified all nine pgcrypto calls across migrations 007 and 008 as `extensions.digest(...)`.
- Regression coverage: complete 001–008 chain executed with no `digest` function in `pg_catalog` or `public`.
- Regression outcome: PASS.
- Seed count after repair validation: 50 students.
- Public RPC count after repair validation: 24.
- Idempotent student-profile submission: PASS.
