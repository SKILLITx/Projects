# Phase 2 Tranche 1 State

## Status

Generated, pending remote dry-run.

## Files

- `supabase/migrations/20260717000100_phase2_foundation_and_tenancy.sql`
- `docs/database/01-foundation-and-tenancy.md`
- `docs/database/01-foundation-catalog-check.sql`
- `database/schema/migration-checksums.json`

## Verification sequence

1. Extract the patch over the repository.
2. Run `npx supabase db push --dry-run`.
3. Confirm that exactly one new migration is pending.
4. Apply only after the dry-run output is reviewed.
5. Run the read-only catalog checks.
6. Repair any failure before creating identity and authorization tables.
