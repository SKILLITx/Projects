# Workflow 08 stabilization

This workflow applies the lessons from Workflows 01 and 02 before activation:

- imports separately and remains inactive;
- corrects every Code-node execution mode and return contract;
- expands claimed notification batches only in all-items mode;
- preserves item linking across multiple notifications;
- uses the already fixed service-role authorization path;
- gives every workflow log a distinct idempotency key;
- retries idempotent Supabase RPCs with finite timeouts;
- does not retry Gmail at node level;
- classifies uncertain Gmail outcomes as dead-letter to prevent duplicate sends;
- records explicit temporary and permanent provider failures;
- validates that the delivery outcome reached Supabase before logging completion;
- keeps execution evidence during pilot testing.

The dispatcher uses a schedule trigger, so it does not depend on Google Form
or Automation Queue row-added events.
