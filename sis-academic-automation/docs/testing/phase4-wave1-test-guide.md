# Phase 4 Wave 1 Test Guide

## Database suite

Run `scripts/Copy-Phase4Wave1Verification.ps1` and execute the copied SQL in Supabase. It rolls back all test data.

Expected result:

```json
{
  "suite": "phase4-wave1-hosted-verification",
  "success": true,
  "test_count": 9,
  "failed_tests": [],
  "transaction_rolled_back": true
}
```

The nine database checks cover the RPC catalog, student idempotency, Cambridge-school guardian validation, duplicate-document rejection, missing-document rejection, valid enrollment allocation, duplicate-course rejection, forbidden-fallback rollback and notification-attempt idempotency.

## Workflow 01

Submit a new Student Profile form using DMU, ISB, BSBA, the current `AYYYYY`, and `FALL`. Confirm:

- queue status becomes `completed`;
- correlation ID is populated;
- student and program registration exist;
- profile acknowledgment appears in the notification outbox;
- resubmitting the same queue request does not duplicate the student or notification.

## Workflow 02

Submit BA101 with preferred section A for the created student. A newly created student without verified documents should receive a stable rejected enrollment outcome for missing required documents. After documents are verified, the same business scenario with a new idempotency key should evaluate section, capacity and timetable rules.

## Workflow 08

Before activation, bind the Gmail credential. Execute manually and confirm:

- a pending profile acknowledgment is claimed;
- one delivery attempt is reserved;
- Gmail sends once;
- outbox status becomes completed;
- manual rerun does not resend the completed notification.
