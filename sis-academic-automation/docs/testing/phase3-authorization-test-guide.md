# Phase 3 Authorization Test Guide

## Preconditions

1. A user exists in **Supabase Auth → Users**.
2. The same user is linked to `staff_profiles.auth_user_id`.
3. An active role assignment exists.
4. Campus administrators also have an active campus assignment.
5. `portal/config.local.js` contains only the project URL and anon key.

## Automated authenticated SQL check

Run:

```powershell
& ".\scripts\Copy-Phase3AuthorizationTest.ps1"
```

Enter the staff email and scope locally. Paste the generated transaction into Supabase SQL Editor and run it once. The transaction rolls back and does not change business data.

Expected result:

```json
{
  "success": true,
  "suite": "phase3-authenticated-authorization-verification",
  "staff_profiles_visible": 1,
  "role_assignments_visible": 1,
  "institutions_visible": 1,
  "dashboard_rpc_success": true
}
```

A super administrator may see more than one role, institution or campus. A campus administrator must not successfully search an unassigned campus.

## Portal checks

- Sign-in succeeds only for a valid Supabase Auth account.
- Staff profile and role scope load through RLS.
- The dashboard RPC succeeds for an allowed institution/campus.
- Student search returns only permitted scope.
- Enrollment, marks and correction decisions reject unauthorized actors.
- Signing out removes the active browser session.
- Browser source contains no service-role key.

## Full matrix

See `phase3-authorization-test-matrix.csv`.
