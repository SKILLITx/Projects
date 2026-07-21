# Phase 2 pgcrypto Extension-Schema Repair

## Failure

Remote application stopped at migration `20260717000700_phase2_public_rpc_contract.sql` with:

```text
function digest(bytea, unknown) does not exist
```

Migrations 003–006 completed before the failure. Migration 007 was wrapped in a transaction, so its failed execution was rolled back and was not recorded as applied. Migration 008 was not attempted.

## Root cause

Supabase installs most PostgreSQL extensions under the `extensions` schema. The RPC migration used a restricted `search_path`, which intentionally did not include that schema, but called `digest(...)` without schema qualification.

## Repair

All pgcrypto calls in the not-yet-applied migrations 007 and 008 now use:

```sql
extensions.digest(...)
```

The restricted function search paths remain unchanged.

## Additional repair

The Windows PowerShell 5.1 static verifier now counts migration properties with an explicit array wrapper, so it prints:

```text
Verified 8 ordered migration file(s).
```

instead of eight separate `1` values.

## Validation performed before packaging

The complete migration chain 001–008 was rerun in a PostgreSQL-compatible validation runtime with `digest` available only as `extensions.digest`. Results:

- all eight migrations executed;
- 50 students loaded;
- 24 public RPC functions existed;
- student-profile RPC returned success;
- repeated idempotent submission returned the same result.

## Safe application boundary

Only migrations 007 and 008 are changed. Migrations 001–006, including the four migrations already applied immediately before this failure, are not modified.
