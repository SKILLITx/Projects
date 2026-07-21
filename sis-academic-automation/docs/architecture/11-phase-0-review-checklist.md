# Phase 0 Review Checklist

Phase 1 may begin only after these items are approved or specifically amended.

## Architecture decisions

- [ ] Supabase PostgreSQL is the only academic system of record; Airtable is excluded.
- [ ] Local n8n + SQLite + ngrok is classified as controlled-pilot infrastructure, not production.
- [ ] The system uses ten business-domain workflows.
- [ ] Google Sheets are intake/reporting surfaces, not authoritative academic storage.
- [ ] Academic rules are stored as versioned institution configuration, not n8n logic.
- [ ] Critical changes occur in PostgreSQL transactions.
- [ ] Notifications use a database outbox.
- [ ] Incidents are deduplicated by a stable fingerprint and correlation context.

## Security decisions

- [ ] Browser code contains only the Supabase URL and anon key.
- [ ] Authenticated staff requests carry a Supabase access token to n8n.
- [ ] Staff RPC authorization derives from `auth.uid()`, role assignments and institution/campus scope.
- [ ] Service-role access is server-side only and limited to named RPC wrappers.
- [ ] Teacher marks submission uses a restricted institutional Google Form or authenticated portal.
- [ ] Public student Forms are validated and processed only through n8n.
- [ ] Optional student Auth is supported but is not required for the initial public-Form pilot.

## Reporting decisions

- [ ] HEC output is labelled a demonstration format until an official template is provided and approved.
- [ ] Gmail provider acceptance is recorded without claiming guaranteed recipient inbox delivery.
- [ ] Dashboard data is generated from a Supabase snapshot.

## Build-sequence decisions

- [ ] Phase 1 begins only after this review.
- [ ] Phase 2 database work is applied and verified before n8n business workflows.
- [ ] Workflow 10 and Workflow 8 are implemented before the main business workflows to establish incident and notification infrastructure.
- [ ] Each workflow is tested independently before the next begins.
- [ ] No pilot-ready claim is made before end-to-end, concurrency, backup and restore tests pass.

## Approval response

Use one of these responses:

```text
Phase 0 approved. Start Phase 1.
```

or:

```text
Change Phase 0 item: <specific item and required change>.
```
