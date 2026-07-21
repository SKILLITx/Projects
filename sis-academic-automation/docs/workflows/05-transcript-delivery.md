# Workflow 05 — Transcript Request, Generation and Delivery

## Outcome

This workflow owns one transcript business outcome:

1. authenticated request and authorization;
2. payload-safe idempotent transcript request creation;
3. complete academic model retrieval;
4. Google Docs transcript rendering;
5. PDF export and Google Drive storage;
6. document metadata registration;
7. durable `transcript.ready` notification outbox creation;
8. delivery-state synchronization from Workflow 08.

## Credentials

Bind these existing n8n credentials after import:

- Google HTTP nodes: `Google Drive account`
- service-only Supabase nodes: `SIS Supabase Service Role`

The request and transcript-model RPC calls use the caller's Supabase bearer token
and the configured public anon key. The service-role key is never returned to the
browser.

## Environment

```text
SIS_TRANSCRIPT_DRIVE_FOLDER_ID=
```

The value is optional. When blank, generated files are created in the connected
Google account's My Drive root. For the pilot, create a folder named
`SIS — Generated Transcripts` and place its folder ID in `.env`, then restart
n8n so the child process receives the value.

The existing Supabase URL and public anon-key variables remain unchanged.

## Delivery boundary

Workflow 05 does not send Gmail directly. It records the PDF and creates one
`transcript.ready` outbox row. The already-published Workflow 08 claims and
delivers the message, preserving global retry and duplicate-delivery controls.
A database trigger synchronizes Workflow 08 delivery attempts back to
`transcript_delivery_records` and marks the transcript request delivered.

## Idempotency

A repeated request with the same institution and idempotency key:

- must match the same student, campus and recipient;
- returns the existing request;
- returns the existing PDF when one is complete;
- never creates a second document, delivery record or notification row.

## Pilot limitation

The generated document is explicitly labelled as a controlled pilot /
demonstration transcript. An institution logo is shown only when an approved
logo URL exists in the institution record.
