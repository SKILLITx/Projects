# Workflow 04 Results Approval and Publication preflight

This preflight captures the exact live Supabase contract before generating
the Workflow 04 migration and n8n workflow.

It inspects:

- result and marks table columns;
- foreign keys, checks, unique constraints and indexes;
- RLS policies;
- enum values;
- existing marks/results/grade/GPA/standing RPC functions;
- the latest finalized marks batch;
- small samples from relevant tables.

The query uses temporary `pg_temp` helper functions only. It does not modify
persistent business data and does not print credentials or secret values.

After the JSON result is reviewed, the next package will contain the complete
Workflow 04 database migration, service-role-safe public RPC, n8n workflow,
configuration checklist and bundled acceptance tests.
