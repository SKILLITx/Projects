# Operator Handover

## Daily startup

1. Run `npm run sis:start` from the repository.
2. Confirm n8n, portal, transcript portal, and ngrok are reachable.
3. Confirm Workflows 01-05, 07, 08, and 09 remain published.
4. Review Workflow 09's latest scheduled execution.
5. Check Workflow 08 for failed or dead-letter notification jobs.

## Workflows that must remain inactive

- Workflow 06 - HEC Reporting
- Workflow 10 - Global Error Handler
- Autobiz Error Handler
- Archived obsolete variants of Workflows 01, 02, 03, 05, and 08

## Incident review

Review the failed n8n execution, sanitized error branch, Workflow 09 snapshot, and relevant durable database records. Do not open large transcript HTML, multipart bodies, binary data, complete headers, or raw access-token input. Retry only when the failure is transient and the workflow remains the single retry owner.

## Data protection

Never share `.env`, `portal/config.local.js`, the n8n encryption key, Supabase service-role keys, OAuth secrets, tokens, authorization headers, private backup ZIPs, or the local n8n SQLite database.

## Change control

Before changing a stabilized workflow, export it, create immutable migrations when required, run static and database verification, run positive and negative acceptance, update project state and changelog, and publish only the stabilized variant.
