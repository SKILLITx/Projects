# Workflow 01 — Student Intake and Profile Management

## Trigger

`Google Sheets Queue Trigger` polls the `Automation Queue` tab linked to the Student Profile and Admission Google Form and emits only newly appended rows.

## Durable boundary

The workflow calls `rpc_submit_student_profile_from_form`. That wrapper resolves institution, campus, program, academic year, term and document codes, hashes the identity reference inside PostgreSQL, and delegates the transaction to `rpc_submit_student_profile`.

## Behaviors

- creates or updates a student safely;
- detects conflicting student number, email and identity matches;
- creates program registration;
- records coded document links;
- records student phone, email and guardian contacts;
- returns missing and pending-verification document codes;
- creates audit and notification-outbox records;
- uses the Google Form response ID as the durable idempotency key;
- updates one queue row with a sanitized result.

## Privacy

Successful and failed n8n execution payload persistence is disabled for this workflow. Google and Supabase access remains permission restricted. The raw identity reference is sent only to the database wrapper, hashed there, and excluded from the durable core request.
