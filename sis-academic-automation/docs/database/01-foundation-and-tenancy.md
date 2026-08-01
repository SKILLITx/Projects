# Phase 2 Database Tranche 1 — Foundation and Tenancy

## Migration

`supabase/migrations/20260717000100_phase2_foundation_and_tenancy.sql`

This first migration creates:

- the internal `app`, `audit`, `ops` and `reporting` schemas;
- shared enum types;
- the shared `updated_at` trigger;
- institutions and campuses;
- versioned institution settings;
- academic years and terms;
- enrollment periods;
- cross-tenant foreign-key protection;
- foundational indexes and validation constraints;
- RLS on every new `public` table.

## Deliberate security boundary

No `anon` or `authenticated` table access is enabled yet. Identity, role assignments and scoped RLS policies are part of the next migration.

This prevents a partially built authorization layer from exposing tenant data.

## Deployment sequence

Preview the linked-project change:

```powershell
npx supabase db push --dry-run
```

Expected result: only `20260717000100_phase2_foundation_and_tenancy.sql` appears as pending.

After reviewing that output, apply it with:

```powershell
npx supabase db push
```

Supabase records applied migration timestamps in `supabase_migrations.schema_migrations`, so later pushes skip migrations that are already present remotely.

## Do not run

- `supabase start`
- `supabase db reset`
- `supabase db reset --linked`
- `supabase migration repair`

Those commands are unnecessary for this tranche, and remote reset is destructive.
