# Phase 4 service-role authorization root-cause fix

## Root cause

The service-role key was not the remaining defect.

The database helper `app.is_service_request()` checked only:

```sql
current_setting('request.jwt.claim.role', true)
```

The real PostgREST request carries the decoded JWT in:

```sql
current_setting('request.jwt.claims', true)
```

as JSON. As a result, real n8n calls were rejected with:

```text
AUTH_SERVICE_ROLE_REQUIRED
```

even when the correct service-role credential was supplied.

The earlier hosted test did not reveal the defect because it manually set the
legacy `request.jwt.claim.role` setting.

## Fix

The new migration reads the current JSON claim first while retaining legacy
compatibility. It does not weaken authorization: `authenticated` and `anon`
roles remain rejected.

No n8n key, credential, workflow expression, or Google Sheet mapping needs to
be changed again.
