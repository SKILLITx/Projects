# Phase 2 Database Tranche 2 — Identity and Authorization

## Migration

`supabase/migrations/20260717000200_phase2_identity_and_authorization.sql`

## Creates

- `staff_profiles`
- `role_assignments`
- `campus_assignments`
- `permission_grants`
- private `audit.authorization_events`
- staff-role and permission enums
- tenant and campus authorization helper functions
- scoped `SELECT` policies for identity and foundation tables

## Security model

Authenticated clients receive only `SELECT` privileges, and RLS determines which rows they can see. Direct client-side writes remain disabled. Later administrative writes will use narrowly scoped RPC functions.

Authorization is derived from:

1. `auth.uid()`;
2. the linked active staff profile;
3. active, time-valid role assignments;
4. institution scope;
5. campus assignments where required;
6. optional permission overrides.

Authorization data is not read from user-editable profile metadata.

## Bootstrap boundary

This migration does not create a first administrator and does not require any secret. A later verified step will create the first Supabase Auth user and link a super-administrator profile without exposing credentials in chat.

## Verification sequence

Preview:

```powershell
npx supabase db push --dry-run
```

Expected pending migration:

```text
20260717000200_phase2_identity_and_authorization.sql
```

Do not apply it until the dry-run output has been reviewed.
