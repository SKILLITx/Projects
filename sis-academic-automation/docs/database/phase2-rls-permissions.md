# Phase 2 RLS and Permissions Guide

## Exposure boundary

- `public` contains RLS-protected business tables and stable RPC wrappers.
- `app`, `audit`, `ops` and `reporting` are not direct PostgREST contracts.
- `anon` receives no table privileges and no Phase 2 business-RPC execution grants.
- `authenticated` receives scoped `SELECT` access and only the administrative or self-service RPCs explicitly required by its role.
- `service_role` is reserved for trusted server-side n8n operations and bypasses RLS by design.

## Authorization chain

1. Supabase Auth supplies `auth.uid()`.
2. `staff_profiles` links the Auth user to a staff record.
3. Active role assignments establish institution scope.
4. Campus assignments narrow campus administrators.
5. Helper functions enforce role, tenant and campus checks.
6. RLS policies filter reads; RPC functions validate and perform controlled writes.

## Write boundary

Authenticated clients are not granted direct insert/update/delete privileges on business tables. Controlled writes run through security-definer RPCs with `search_path = ''`, fully qualified object names, stable errors and transaction boundaries.

## First administrator

No password or first Auth user is included in migrations or seed data. Bootstrap is a separate Phase 3 action so credentials never enter the repository or chat.
