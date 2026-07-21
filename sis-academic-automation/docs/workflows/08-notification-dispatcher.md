# Workflow 08 — Notification Dispatcher

## Pattern

The workflow uses the database outbox pattern and runs once per minute.

1. Claim a bounded batch with `FOR UPDATE SKIP LOCKED` semantics.
2. Reserve an attempt before calling Gmail.
3. Skip the provider call when the attempt already exists.
4. Send one text email without node-level provider retries.
5. Idempotently finalize the reserved attempt.
6. Apply database-owned exponential backoff or dead-letter state.

## Duplicate prevention

`rpc_begin_notification_attempt` creates the unique `(outbox_id, attempt_number)` record before Gmail is called. A replay returns `should_send=false`.

If the workflow stops after a provider call but before its result is recorded, the outcome is uncertain. The next claim cycle dead-letters that stale running attempt rather than sending a possible duplicate. Staff can review the incident manually.

## Channels

Gmail is active for the controlled pilot. WhatsApp, SMS and internal notifications remain modeled in the outbox but are recorded as non-retryable configuration failures until a provider is explicitly added.

## Recording failures

The workflow does not report a completed run when the delivery-recording RPC fails. The outbox remains recoverable through stale-attempt handling and later operations monitoring.
